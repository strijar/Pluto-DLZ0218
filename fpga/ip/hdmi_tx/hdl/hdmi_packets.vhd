-- HDMI packet layouts: HDMI 1.3 sections 5.2-5.3, 7.8, 8.2.
-- All byte/bit vectors are transmitted least-significant bit first.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package hdmi_packets is
  subtype byte_t is std_logic_vector(7 downto 0);
  subtype symbol_t is std_logic_vector(9 downto 0);
  type symbols_t is array (0 to 2) of symbol_t;
  type subpackets_t is array (0 to 3) of std_logic_vector(55 downto 0);
  type packet_t is record
    header : std_logic_vector(23 downto 0);
    sub : subpackets_t;
  end record;
  constant NULL_PACKET : packet_t := ((others => '0'), (others => (others => '0')));
  function terc4(n : std_logic_vector(3 downto 0)) return symbol_t;
  function control(c : std_logic_vector(1 downto 0)) return symbol_t;
  function ecc(v : std_logic_vector) return byte_t;
  function infoframe(kind : natural) return packet_t;
  function acr_packet return packet_t;
  function audio_packet(pcm : std_logic_vector(31 downto 0); frame : natural) return packet_t;
end package;

package body hdmi_packets is
  function terc4(n : std_logic_vector(3 downto 0)) return symbol_t is
    type table_t is array (0 to 15) of symbol_t;
    constant t : table_t := (
      "1010011100", "1001100011", "1011100100", "1011100010",
      "0101110001", "0100011110", "0110001110", "0100111100",
      "1011001100", "0100111001", "0110011100", "1011000110",
      "1010001110", "1001110001", "0101100011", "1011000011");
  begin return t(to_integer(unsigned(n))); end;

  function control(c : std_logic_vector(1 downto 0)) return symbol_t is
  begin
    case c is
      when "00" => return "1101010100";
      when "01" => return "0010101011";
      when "10" => return "0101010100";
      when others => return "1010101011";
    end case;
  end;

  function ecc(v : std_logic_vector) return byte_t is
    variable r : unsigned(7 downto 0) := (others => '0');
    variable feedback : std_logic;
  begin
    for i in 0 to v'length-1 loop
      feedback := r(0) xor v(v'low+i);
      r := shift_right(r, 1);
      if feedback = '1' then r := r xor x"83"; end if;
    end loop;
    return std_logic_vector(r);
  end;

  function infoframe(kind : natural) return packet_t is
    variable p : packet_t := NULL_PACKET;
    type bytes_t is array(0 to 27) of byte_t;
    variable b : bytes_t := (others => (others => '0'));
    variable sum : natural := 0;
  begin
    if kind = 16#82# then
      p.header := x"0D0282";
      -- RGB, no bars, underscan; 4:3 picture, no active-format indication.
      -- IT content, full RGB range; VESA mode has no CTA VIC.
      b(1) := x"02"; b(2) := x"10"; b(3) := x"88";
    else
      p.header := x"0A0184";
      b(1) := x"01"; -- 2 channels; coding/rate/width refer to stream header.
    end if;

    for i in 0 to 2 loop sum := sum + to_integer(unsigned(p.header(i*8+7 downto i*8))); end loop;
    for i in 1 to 27 loop sum := sum + to_integer(unsigned(b(i))); end loop;

    b(0) := std_logic_vector(to_unsigned((256 - (sum mod 256)) mod 256, 8));

    for s in 0 to 3 loop
      for j in 0 to 6 loop p.sub(s)(j*8+7 downto j*8) := b(s*7+j); end loop;
    end loop;
    return p;
  end;

  function acr_packet return packet_t is
    variable p : packet_t := NULL_PACKET;
  begin
    p.header := x"000001";
    -- Bytes: reserved, CTS[19:16], CTS[15:8], CTS[7:0], N[19:16], N[15:8], N[7:0].
    p.sub := (others => x"001800409C0000");
    return p;
  end;

  function audio_packet(pcm : std_logic_vector(31 downto 0); frame : natural) return packet_t is
    variable p : packet_t := NULL_PACKET;
    variable status : std_logic_vector(191 downto 0);
    variable sample : std_logic_vector(23 downto 0);
    variable parity, c : std_logic;
  begin
    p.header := x"000102"; -- layout 0, subpacket 0 present; no flatline flags.

    if frame = 0 then p.header(20) := '1'; end if;

    for ch in 0 to 1 loop
      status := (others => '0');
      status(7 downto 0) := x"04"; -- consumer LPCM, copyright not asserted.
      status(23 downto 16) := std_logic_vector(to_unsigned((ch+1)*16, 8));
      status(31 downto 24) := x"02"; -- 48 kHz.
      status(39 downto 32) := x"D2"; -- original 48 kHz, 16-bit word (20-bit maximum).
      c := status(frame);
      sample := pcm(ch*16+15 downto ch*16) & x"00"; -- MSB-aligned within 24 bits.
      parity := c;
      for i in 0 to 23 loop parity := parity xor sample(i); end loop;
      p.sub(0)(ch*24+23 downto ch*24) := sample;
      p.sub(0)(48+ch*4+3 downto 48+ch*4) := parity & c & "00";
    end loop;
    return p;
  end;

end package body;
