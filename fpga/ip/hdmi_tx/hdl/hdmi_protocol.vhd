-- Fixed 800x600@40MHz HDMI scheduler and parallel symbol encoder.
-- Input raster coordinates must be aligned to RGB/DE/HS/VS.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_packets.all;

entity hdmi_protocol is
  port (pixel_clk, resetn : in std_logic;
        rgb : in std_logic_vector(23 downto 0);
        de, hsync, vsync : in std_logic;
        pixel_x : in std_logic_vector(10 downto 0);
        pixel_y : in std_logic_vector(9 downto 0);
        pcm_data : in std_logic_vector(31 downto 0); -- L[15:0], R[31:16]
        pcm_valid : in std_logic;
        pcm_ready : out std_logic;
        symbols : out symbols_t);
end entity;

architecture rtl of hdmi_protocol is
  type fifo_t is array(0 to 15) of std_logic_vector(31 downto 0);
  signal fifo : fifo_t;
  signal wr, rd : natural range 0 to 15 := 0;
  signal used : natural range 0 to 16 := 0;
  signal audio_frame : natural range 0 to 191 := 0;
  signal acr_timer : natural range 0 to 39999 := 0;
  signal acr_pending : std_logic := '0';
  signal avi_pending, aif_pending : std_logic := '1';
  signal packet : packet_t := NULL_PACKET;
  type blocks_t is array(0 to 3) of std_logic_vector(63 downto 0);
  signal blocks : blocks_t := (others => (others => '0'));
  signal header_block : std_logic_vector(31 downto 0) := (others => '0');
  signal x : natural range 0 to 2047;
  signal y : natural range 0 to 1023;
  signal aux : symbols_t;
  type pipe_t is array(0 to 2) of symbols_t;
  signal aux_pipe : pipe_t := (others => (others => "1101010100"));
  signal video_pipe : std_logic_vector(0 to 2) := (others => '0');
  signal encoded : symbols_t;
  signal video_enable, armed : std_logic := '0';

begin

  x <= to_integer(unsigned(pixel_x)); y <= to_integer(unsigned(pixel_y));
  pcm_ready <= '1' when used < 16 and resetn = '1' else '0';
  video_enable <= de and armed and resetn;

  -- Digilent pipeline has three registers; aux modes have the same latency.

  encoders : for ch in 0 to 2 generate
    encoder : entity work.TMDS_Encoder port map (
      PixelClk => pixel_clk, SerialClk => pixel_clk, aRst => '0',
      pDataOutRaw => encoded(ch), pDataOut => rgb(ch*8+7 downto ch*8),
      pC0 => '0', pC1 => '0', pVde => video_enable);
    symbols(ch) <= encoded(ch) when video_pipe(2) = '1' else aux_pipe(2)(ch);
  end generate;

  process(pixel_clk)
    variable p : packet_t;
    variable push, pop : boolean;
  begin
    if rising_edge(pixel_clk) then
      if resetn = '0' then
        wr <= 0; rd <= 0; used <= 0; audio_frame <= 0;
        acr_timer <= 0; acr_pending <= '0'; avi_pending <= '1'; aif_pending <= '1';
        packet <= NULL_PACKET; header_block <= (others => '0');
        blocks <= (others => (others => '0'));
        video_pipe <= (others => '0'); aux_pipe <= (others => (others => "1101010100"));
        armed <= '0';
      else
        aux_pipe(0) <= aux; aux_pipe(1) <= aux_pipe(0); aux_pipe(2) <= aux_pipe(1);
        video_pipe(0) <= video_enable; video_pipe(1) <= video_pipe(0); video_pipe(2) <= video_pipe(1);

        if x = 1055 then armed <= '1'; end if;

        push := pcm_valid = '1' and used < 16;
        pop := false;

        if push then fifo(wr) <= pcm_data; wr <= (wr + 1) mod 16; end if;

        -- Prepare each packet one clock before its first TERC4 character.
        if x = 817 or x = 849 or x = 881 or x = 913 then
          p := NULL_PACKET;
          if aif_pending = '1' then
            p := infoframe(16#84#); aif_pending <= '0';
          elsif used > 0 then
            p := audio_packet(fifo(rd), audio_frame); pop := true;
            rd <= (rd + 1) mod 16;
            if audio_frame = 191 then audio_frame <= 0; else audio_frame <= audio_frame + 1; end if;
          elsif acr_pending = '1' then
            p := acr_packet; acr_pending <= '0';
          elsif avi_pending = '1' then
            p := infoframe(16#82#); avi_pending <= '0';
          end if;

          packet <= p;
          header_block <= ecc(p.header) & p.header;

          for i in 0 to 3 loop blocks(i) <= ecc(p.sub(i)) & p.sub(i); end loop;
        end if;

        if push and not pop then used <= used + 1;
        elsif pop and not push then used <= used - 1; end if;

        if acr_timer = 39999 then
          acr_timer <= 0;
          assert acr_pending = '0' report "ACR deadline missed" severity failure;
          acr_pending <= '1';
        else acr_timer <= acr_timer + 1; end if;

        if x = 0 and y = 0 then avi_pending <= '1'; aif_pending <= '1'; end if;

      end if;
    end if;
  end process;

  process(x, y, hsync, vsync, blocks, header_block)
    variable a : symbols_t;
    variable nibble0, nibble1, nibble2 : std_logic_vector(3 downto 0);
    variable index : natural range 0 to 31;
    variable next_active : boolean;
  begin
    a := (others => control("00"));
    a(0) := control(vsync & hsync);
    next_active := y < 599 or y = 627;

    if x >= 808 and x < 816 then
      a(1) := control("01"); a(2) := control("01");
    elsif (x >= 816 and x < 818) or (x >= 946 and x < 948) then
      a(0) := terc4("11" & vsync & hsync);
      a(1) := "0100110011"; a(2) := "0100110011";
    elsif x >= 818 and x < 946 then
      index := (x - 818) mod 32;
      nibble0 := '1' & header_block(index) & vsync & hsync;

      for i in 0 to 3 loop
        nibble1(i) := blocks(i)(2*index); nibble2(i) := blocks(i)(2*index+1);
      end loop;

      a(0) := terc4(nibble0); a(1) := terc4(nibble1); a(2) := terc4(nibble2);
    elsif next_active and x >= 1046 and x < 1054 then
      a(1) := control("01");
    elsif next_active and x >= 1054 and x < 1056 then
      a(0) := "1011001100"; a(1) := "0100110011"; a(2) := "1011001100";
    end if;

    aux <= a;
  end process;

end architecture;
