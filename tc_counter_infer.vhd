-------------------------------------------------------------------------------
-- tc_counter_infer.vhd
--
-- MicroZed Chronicles: Flags for Free
--
-- The inference experiment: the fabric counter again, written behaviourally,
-- but with the USE_DSP attribute asking Vivado synthesis to put the counter
-- into a DSP slice. The question the article asks is whether Vivado also maps
-- the equality compare and the clear-on-match into the slice's pattern
-- detector, or leaves them in LUTs around a DSP that only does the addition.
-- Look at the DSP48E2 attributes in the synthesised netlist
-- (report_property on the cell, or the schematic) for USE_PATTERN_DETECT,
-- PATTERN, MASK and AUTORESET_PATDET to find out.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tc_counter_infer is
  generic (
    TC : natural := 9
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    en      : in  std_logic;
    count   : out std_logic_vector(47 downto 0);
    tc_flag : out std_logic
  );
end entity tc_counter_infer;

architecture rtl of tc_counter_infer is

  constant C_TC : unsigned(47 downto 0) := to_unsigned(TC, 48);

  signal cnt  : unsigned(47 downto 0) := (others => '0');
  signal flag : std_logic := '0';

  attribute use_dsp : string;
  attribute use_dsp of cnt : signal is "yes";

begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' or (en = '1' and flag = '1') then
        cnt <= (others => '0');
      elsif en = '1' then
        cnt <= cnt + 1;
      end if;
      if rst = '1' then
        flag <= '0';
      elsif en = '1' then
        if flag = '0' and cnt + 1 = C_TC then
          flag <= '1';
        else
          flag <= '0';
        end if;
      end if;
    end if;
  end process;

  count   <= std_logic_vector(cnt);
  tc_flag <= flag;

end architecture rtl;
