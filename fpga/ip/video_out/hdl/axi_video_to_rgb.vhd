-- Fixed 800x600 RGB888 AXIS sink. Upstream AXIS FIFO supplies elasticity.
-- On starvation or malformed SOF/EOL discard the rest of the frame and seek
-- the next SOF. A held SOF is only accepted at the next raster origin.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_video_to_rgb is
  port (aclk, aresetn : in std_logic;
        s_axis_tdata : in std_logic_vector(23 downto 0);
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        s_axis_tuser : in std_logic_vector(0 downto 0);
        s_axis_tlast : in std_logic;
        rgb : out std_logic_vector(23 downto 0);
        de, hsync, vsync : out std_logic;
        fault : out std_logic;
        pixel_x : out std_logic_vector(10 downto 0);
        pixel_y : out std_logic_vector(9 downto 0));
end entity;

architecture rtl of axi_video_to_rgb is
  signal x : unsigned(10 downto 0);
  signal y : unsigned(9 downto 0);
  signal active, hs, vs, ready_i : std_logic;
  signal running : std_logic := '0';
  signal origin : boolean;

begin

  timing : entity work.video_timing_gen
    port map (aclk, aresetn, x, y, active, hs, vs);

  origin <= x = 0 and y = 0;

  ready_i <= '0' when aresetn = '0' else
             active when running = '1' else
             '1' when s_axis_tuser(0) = '0' or origin else '0';
  s_axis_tready <= ready_i;

  process(aclk)
    variable take, good : boolean;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        running <= '0'; rgb <= (others => '0');
        pixel_x <= (others => '0'); pixel_y <= (others => '0');
        de <= '0'; hsync <= '0'; vsync <= '0'; fault <= '0';
      else
        -- Register timing together with pixels, including the black fallback.
        pixel_x <= std_logic_vector(x); pixel_y <= std_logic_vector(y);
        de <= active; hsync <= hs; vsync <= vs; rgb <= (others => '0');
        take := s_axis_tvalid = '1' and ready_i = '1';

        if active = '1' and (running = '1' or
           (origin and take and s_axis_tuser(0) = '1')) then
          good := take and ((s_axis_tlast = '1') = (x = 799)) and
                  ((s_axis_tuser(0) = '1') = origin);

          if good then
            rgb <= s_axis_tdata;
            running <= '1';
            if x = 799 and y = 599 then running <= '0'; end if;
          else
            running <= '0'; fault <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
