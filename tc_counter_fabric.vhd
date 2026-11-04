-------------------------------------------------------------------------------
-- tc_counter_fabric.vhd
--
-- MicroZed Chronicles: Flags for Free
--
-- The fabric reference for tc_counter_dsp: a 48-bit counter, a 48-bit
-- equality compare and the same automatic reset to zero on the cycle after
-- the terminal count. Same ports, same cycle behaviour, so the two can be
-- swapped in a testbench or compared in report_utilization.
--
-- tc_flag is registered so that it lines up with count exactly as the DSP
-- version's PATTERNDETECT does.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tc_counter_fabric is
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
end entity tc_counter_fabric;

architecture rtl of tc_counter_fabric is

  constant C_TC : unsigned(47 downto 0) := to_unsigned(TC, 48);

  signal cnt  : unsigned(47 downto 0) := (others => '0');
  signal flag : std_logic := '0';

begin

  process (clk)
    variable nxt : unsigned(47 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt  <= (others => '0');
        flag <= '0';
      elsif en = '1' then
        if flag = '1' then           -- the cycle after the match
          nxt := (others => '0');
        else
          nxt := cnt + 1;
        end if;
        cnt <= nxt;
        if nxt = C_TC then           -- the 48-bit compare
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
