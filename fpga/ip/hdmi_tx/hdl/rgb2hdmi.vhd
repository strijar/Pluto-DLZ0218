-- Board-tested Digilent OSERDES and output buffers, now fed HDMI symbols.
library ieee;
use ieee.std_logic_1164.all;
use work.hdmi_packets.all;

entity rgb2hdmi is
  generic (TEST_TONE : boolean := false);
  port (pixel_clk, serial_clk, resetn : in std_logic;
        rgb : in std_logic_vector(23 downto 0);
        de, hsync, vsync : in std_logic;
        pixel_x : in std_logic_vector(10 downto 0);
        pixel_y : in std_logic_vector(9 downto 0);
        pcm_data : in std_logic_vector(31 downto 0);
        pcm_valid : in std_logic; pcm_ready : out std_logic;
        TMDS_Clk_p, TMDS_Clk_n : out std_logic;
        TMDS_Data_p, TMDS_Data_n : out std_logic_vector(2 downto 0));
end entity;

architecture rtl of rgb2hdmi is
  signal symbols : symbols_t;
  signal pcm : std_logic_vector(31 downto 0);
  signal valid, ready, rst, async_rst : std_logic;

begin

  async_rst <= not resetn;

  reset_bridge : entity work.ResetBridge
    generic map (kPolarity => '1')
    port map (aRst => async_rst, OutClk => pixel_clk, oRst => rst);

  test_source : if TEST_TONE generate
    tone : entity work.hdmi_test_tone port map (pixel_clk, resetn, ready, pcm, valid);
    pcm_ready <= '1';
  end generate;

  linux_source : if not TEST_TONE generate
    pcm <= pcm_data; valid <= pcm_valid; pcm_ready <= ready;
  end generate;

  protocol : entity work.hdmi_protocol
    port map (pixel_clk, resetn, rgb, de, hsync, vsync, pixel_x, pixel_y,
              pcm, valid, ready, symbols);

  clock_serializer : entity work.OutputSERDES
    generic map(kParallelWidth => 10)
    port map(PixelClk => pixel_clk, SerialClk => serial_clk, pDataOut => "1111100000",
             sDataOut_p => TMDS_Clk_p, sDataOut_n => TMDS_Clk_n, aRst => rst);

  serializers : for ch in 0 to 2 generate
    serializer : entity work.OutputSERDES
      generic map(kParallelWidth => 10)
      port map(PixelClk => pixel_clk, SerialClk => serial_clk, pDataOut => symbols(ch),
               sDataOut_p => TMDS_Data_p(ch), sDataOut_n => TMDS_Data_n(ch), aRst => rst);
  end generate;

end architecture;
