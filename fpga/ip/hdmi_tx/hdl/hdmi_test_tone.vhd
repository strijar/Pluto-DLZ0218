-- 1 kHz sine, -12 dBFS peak, stereo in phase. Pixel clock must be 40 MHz.
library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_test_tone is
  port (clk, resetn, ready : in std_logic;
        data : out std_logic_vector(31 downto 0);
        valid : out std_logic);
end entity;

architecture rtl of hdmi_test_tone is
  type rom_t is array (0 to 47) of integer range -8191 to 8191;
  constant sine : rom_t := (0, 1069, 2120, 3135, 4095, 4986, 5792, 6498, 7094, 7567, 7912, 8121, 8191, 8121, 7912, 7567, 7094, 6498, 5792, 4986, 4095, 3135, 2120, 1069, 0, -1069, -2120, -3135, -4095, -4986, -5792, -6498, -7094, -7567, -7912, -8121, -8191, -8121, -7912, -7567, -7094, -6498, -5792, -4986, -4096, -3135, -2120, -1069);
  signal accumulator : natural range 0 to 2499 := 0;
  signal phase : natural range 0 to 47 := 0;
  signal pending : std_logic := '0';

begin

  valid <= pending;
  process(clk)
    variable sample : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        accumulator <= 0; phase <= 0; pending <= '0'; data <= (others => '0');
      else
        if ready = '1' then pending <= '0'; end if;

        if accumulator >= 2497 then
          accumulator <= accumulator - 2497;
          assert pending = '0' or ready = '1' report "Tone source backpressured for a full sample period" severity failure;
          sample := std_logic_vector(to_signed(sine(phase), 16));
          data <= sample & sample; pending <= '1';
          if phase = 47 then phase <= 0; else phase <= phase + 1; end if;
        else accumulator <= accumulator + 3;
        end if;
      end if;
    end if;
  end process;

end architecture;
