library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_timing_gen is
  port (clk, resetn : in std_logic;
        x : out unsigned(10 downto 0); y : out unsigned(9 downto 0);
        de, hsync, vsync : out std_logic);
end entity;

architecture rtl of video_timing_gen is
  signal h : natural range 0 to 1055 := 0;
  signal v : natural range 0 to 627 := 0;

begin

  process(clk) begin
    if rising_edge(clk) then
      if resetn = '0' then h <= 0; v <= 0;
      elsif h = 1055 then
        h <= 0;
        if v = 627 then v <= 0; else v <= v + 1; end if;
      else h <= h + 1;
      end if;
    end if;
  end process;

  x <= to_unsigned(h, x'length); y <= to_unsigned(v, y'length);
  de <= '1' when h < 800 and v < 600 else '0';
  hsync <= '1' when h >= 840 and h < 968 else '0';
  vsync <= '1' when v >= 601 and v < 605 else '0';

end architecture;
