-- ADI axi-i2s TX register/DMA ABI; fixed 48 kHz, S32_LE container -> PCM16.
-- DMA0 request/ack clock MUST equal s_axi_aclk. Single-word requests only.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_hdmi_audio is
  port (
    s_axi_aclk, s_axi_aresetn : in std_logic;
    s_axi_awaddr : in std_logic_vector(15 downto 0);
    s_axi_awprot : in std_logic_vector(2 downto 0);
    s_axi_awvalid : in std_logic; s_axi_awready : out std_logic;
    s_axi_wdata : in std_logic_vector(31 downto 0);
    s_axi_wstrb : in std_logic_vector(3 downto 0);
    s_axi_wvalid : in std_logic; s_axi_wready : out std_logic;
    s_axi_bresp : out std_logic_vector(1 downto 0);
    s_axi_bvalid : out std_logic; s_axi_bready : in std_logic;
    s_axi_araddr : in std_logic_vector(15 downto 0);
    s_axi_arprot : in std_logic_vector(2 downto 0);
    s_axi_arvalid : in std_logic; s_axi_arready : out std_logic;
    s_axi_rdata : out std_logic_vector(31 downto 0);
    s_axi_rresp : out std_logic_vector(1 downto 0);
    s_axi_rvalid : out std_logic; s_axi_rready : in std_logic;
    dma_drvalid : out std_logic; dma_drready : in std_logic;
    dma_drtype : out std_logic_vector(1 downto 0); dma_drlast : out std_logic;
    dma_davalid : in std_logic; dma_daready : out std_logic;
    dma_datype : in std_logic_vector(1 downto 0);
    pixel_clk, pixel_resetn : in std_logic;
    pcm_data : out std_logic_vector(31 downto 0);
    pcm_valid : out std_logic; pcm_ready : in std_logic
  );
end entity;

architecture rtl of axi_hdmi_audio is
  constant AW : natural := 8; -- 256 complete stereo pairs, 5.33 ms.
  subtype ptr_t is unsigned(AW downto 0);
  type ram_t is array(0 to 2**AW-1) of std_logic_vector(31 downto 0);
  signal ram : ram_t;
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
  signal wb, wg, rb, rg : ptr_t := (others => '0');
  signal rg_s1, rg_s2, wg_s1, wg_s2 : ptr_t := (others => '0');
  signal full, empty : std_logic;
  signal control_reg : std_logic := '0';
  signal clock_reg : std_logic_vector(31 downto 0) := (others => '0');
  signal enabled : std_logic := '0';
  signal en_s1, en_s2 : std_logic := '0';
  signal left_sample : std_logic_vector(15 downto 0);
  signal half_pair : std_logic := '0';
  signal aw_pending, w_pending, bv, rv : std_logic := '0';
  signal aw_addr : std_logic_vector(15 downto 0);
  signal w_data : std_logic_vector(31 downto 0);
  signal w_strobe : std_logic_vector(3 downto 0);
  type reset_state_t is (ASSERT_RESET, RELEASE_RESET, RUNNING);
  signal reset_state : reset_state_t := ASSERT_RESET;
  signal reset_hold, reset_ack : std_logic := '0';
  signal hold_s1, hold_s2, ack_s1, ack_s2 : std_logic := '0';
  signal common_resetn : std_logic;
  signal axi_run, pix_run : std_logic := '0';
  signal axi_rst_pipe, pix_rst_pipe : std_logic_vector(2 downto 0) := (others => '0');
  type request_state_t is (IDLE, REQUEST_WORD, WAIT_ACK, FLUSH_ACK);
  signal request_state : request_state_t := IDLE;
  signal phase : natural range 0 to 2499 := 0;
  signal pcm_pending, underrun : std_logic := '0';
  signal under_s1, under_s2 : std_logic := '0';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rg_s1, rg_s2, wg_s1, wg_s2, en_s1, en_s2,
    hold_s1, hold_s2, ack_s1, ack_s2, under_s1, under_s2,
    axi_rst_pipe, pix_rst_pipe : signal is "TRUE";

  function gray(b : ptr_t) return ptr_t is
  begin return b xor shift_right(b,1); end;

  function merge_bytes(old, value : std_logic_vector(31 downto 0);
                       strobe : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable v : std_logic_vector(31 downto 0) := old;
  begin
    for i in 0 to 3 loop
      if strobe(i) = '1' then v(i*8+7 downto i*8) := value(i*8+7 downto i*8); end if;
    end loop;
    return v;
  end;

begin

  common_resetn <= s_axi_aresetn and pixel_resetn;

  process(s_axi_aclk, common_resetn) begin
    if common_resetn = '0' then axi_rst_pipe <= (others => '0');
    elsif rising_edge(s_axi_aclk) then axi_rst_pipe <= axi_rst_pipe(1 downto 0) & '1'; end if;
  end process;

  process(pixel_clk, common_resetn) begin
    if common_resetn = '0' then pix_rst_pipe <= (others => '0');
    elsif rising_edge(pixel_clk) then pix_rst_pipe <= pix_rst_pipe(1 downto 0) & '1'; end if;
  end process;

  full <= '1' when wg = (rg_s2 xor to_unsigned(3*2**(AW-1), AW+1)) else '0';
  empty <= '1' when rg = wg_s2 else '0';

  -- Register control crossings and the final local reset enables. The latter
  -- prevent asynchronous assertion from reaching BRAM control pins.

  process(s_axi_aclk) begin
    if rising_edge(s_axi_aclk) then
      axi_run <= axi_rst_pipe(2);
      if control_reg = '1' and clock_reg = x"001F0000" then enabled <= '1';
      else enabled <= '0'; end if;
      if reset_state = ASSERT_RESET then reset_hold <= '1';
      else reset_hold <= '0'; end if;
    end if;
  end process;

  process(pixel_clk) begin
    if rising_edge(pixel_clk) then pix_run <= pix_rst_pipe(2); end if;
  end process;

  s_axi_awready <= not aw_pending and not bv and axi_run;
  s_axi_wready <= not w_pending and not bv and axi_run;
  s_axi_bvalid <= bv;
  s_axi_arready <= not rv and axi_run;
  s_axi_rvalid <= rv;
  pcm_valid <= pcm_pending;
  dma_drvalid <= '1' when request_state = REQUEST_WORD or request_state = FLUSH_ACK else '0';
  dma_drtype <= "10" when request_state = FLUSH_ACK else "00";
  dma_drlast <= '0'; dma_daready <= axi_run;

  process(s_axi_aclk)
    variable value : std_logic_vector(31 downto 0);
    variable flush : boolean;
  begin
    if rising_edge(s_axi_aclk) then
      rg_s1 <= rg; rg_s2 <= rg_s1;
      ack_s1 <= reset_ack; ack_s2 <= ack_s1;
      under_s1 <= underrun; under_s2 <= under_s1;

      if axi_run = '0' then
        wb <= (others => '0'); wg <= (others => '0'); half_pair <= '0';
        control_reg <= '0'; clock_reg <= (others => '0');
        aw_pending <= '0'; w_pending <= '0'; bv <= '0'; rv <= '0';
        s_axi_bresp <= "00"; s_axi_rresp <= "00"; s_axi_rdata <= (others => '0');
        reset_state <= ASSERT_RESET; request_state <= IDLE;
        rg_s1 <= (others => '0'); rg_s2 <= (others => '0');
        ack_s1 <= '0'; ack_s2 <= '0'; under_s1 <= '0'; under_s2 <= '0';
      else
        flush := false;
        if reset_state = ASSERT_RESET and ack_s2 = '1' then reset_state <= RELEASE_RESET;
        elsif reset_state = RELEASE_RESET and ack_s2 = '0' then reset_state <= RUNNING; end if;

        if bv = '1' and s_axi_bready = '1' then bv <= '0'; end if;
        if rv = '1' and s_axi_rready = '1' then rv <= '0'; end if;

        if s_axi_awvalid = '1' and aw_pending = '0' and bv = '0' then
          aw_addr <= s_axi_awaddr; aw_pending <= '1'; end if;

        if s_axi_wvalid = '1' and w_pending = '0' and bv = '0' then
          w_data <= s_axi_wdata; w_strobe <= s_axi_wstrb; w_pending <= '1'; end if;

        if s_axi_arvalid = '1' and rv = '0' then
          value := (others => '0'); s_axi_rresp <= "00";
          case s_axi_araddr is
            when x"0000" => null;
            when x"0004" => value(0) := control_reg;
            when x"0008" => value := clock_reg;
            when x"0010" =>
              value(0) := under_s2; value(1) := full; value(2) := half_pair;
              if reset_state /= RUNNING then value(3) := '1'; end if;
              if clock_reg /= x"001F0000" then value(4) := '1'; end if;
            when others => s_axi_rresp <= "10";
          end case;
          s_axi_rdata <= value; rv <= '1';
        end if;

        if aw_pending = '1' and w_pending = '1' and bv = '0' then
          -- Backpressure a complete FIFO pair. Other registers remain responsive
          -- once the preceding transaction finishes. Disabled/in-flight DMA writes
          -- are acknowledged and discarded, allowing DMA termination to complete.
          if aw_addr /= x"002C" or full = '0' or enabled = '0' or reset_state /= RUNNING then
            aw_pending <= '0'; w_pending <= '0'; bv <= '1'; s_axi_bresp <= "00";

            case aw_addr is
              when x"0000" =>
                value := merge_bytes(x"00000000", w_data, w_strobe);
                if value(0) = '1' or value(1) = '1' then flush := true; end if;
                if value(0) = '1' then control_reg <= '0'; clock_reg <= (others => '0'); end if;
              when x"0004" =>
                value := (others => '0'); value(0) := control_reg;
                value := merge_bytes(value, w_data, w_strobe);
                control_reg <= value(0);
                if control_reg = '1' and value(0) = '0' then flush := true; end if;
              when x"0008" =>
                value := merge_bytes(clock_reg, w_data, w_strobe) and x"00FF00FF";
                clock_reg <= value;
                if value /= x"001F0000" then s_axi_bresp <= "10"; end if;
              when x"002C" =>
                if w_strobe /= "1111" then s_axi_bresp <= "10";
                elsif enabled = '1' and reset_state = RUNNING then
                  if half_pair = '0' then
                    left_sample <= w_data(31 downto 16); half_pair <= '1';
                  else
                    ram(to_integer(wb(AW-1 downto 0))) <= w_data(31 downto 16) & left_sample;
                    wb <= wb+1; wg <= gray(wb+1); half_pair <= '0';
                  end if;
                end if;
              when others => s_axi_bresp <= "10";
            end case;
          end if;
        end if;

        if flush or reset_state /= RUNNING then
          wb <= (others => '0'); wg <= (others => '0'); half_pair <= '0';
        end if;

        if flush then reset_state <= ASSERT_RESET; end if;

        -- UG585 single-word request/ack. FLUSH always wins, even while disabled.

        if dma_davalid = '1' and dma_datype = "10" then request_state <= FLUSH_ACK;
        else
          case request_state is
            when IDLE =>
              if enabled = '1' and full = '0' and reset_state = RUNNING and not flush then
                request_state <= REQUEST_WORD;
              end if;
            when REQUEST_WORD =>
              if dma_drready = '1' then
                if dma_davalid = '1' and dma_datype = "00" then request_state <= IDLE;
                else request_state <= WAIT_ACK; end if;
              end if;
            when WAIT_ACK =>
              if (dma_davalid = '1' and dma_datype = "00") or flush then request_state <= IDLE; end if;
            when FLUSH_ACK => if dma_drready = '1' then request_state <= IDLE; end if;
          end case;
        end if;
      end if;
    end if;
  end process;

  process(pixel_clk)
  begin
    if rising_edge(pixel_clk) then
      wg_s1 <= wg; wg_s2 <= wg_s1;
      en_s1 <= enabled; en_s2 <= en_s1;
      hold_s1 <= reset_hold; hold_s2 <= hold_s1;

      if pix_run = '0' then
        wg_s1 <= (others => '0'); wg_s2 <= (others => '0');
        en_s1 <= '0'; en_s2 <= '0'; hold_s1 <= '1'; hold_s2 <= '1';
        rb <= (others => '0'); rg <= (others => '0'); reset_ack <= '0';
        phase <= 0; pcm_pending <= '0'; pcm_data <= (others => '0'); underrun <= '0';
      else
        reset_ack <= hold_s2;

        if pcm_ready = '1' then pcm_pending <= '0'; end if;

        if hold_s2 = '1' then
          rb <= (others => '0'); rg <= (others => '0'); underrun <= '0';
        end if;

        -- HDMI clock/ticks run continuously, even while ALSA is stopped.

        if phase >= 2497 then
          phase <= phase-2497;

          assert pcm_pending = '0' or pcm_ready = '1' report "HDMI PCM sink stalled" severity failure;
          pcm_data <= (others => '0'); pcm_pending <= '1';

          if en_s2 = '1' and hold_s2 = '0' then
            if empty = '0' then
              pcm_data <= ram(to_integer(rb(AW-1 downto 0)));
              rb <= rb+1; rg <= gray(rb+1);
            else underrun <= '1'; end if;
          end if;
        else phase <= phase+3; end if;
      end if;
    end if;
  end process;

end architecture;
