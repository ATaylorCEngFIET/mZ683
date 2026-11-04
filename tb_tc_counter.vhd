-------------------------------------------------------------------------------
-- tb_tc_counter.vhd
--
-- Self-checking testbench for the terminal count counter. VARIANT selects
-- "dsp"    tc_counter_dsp    (needs the UNISIM library, run in Vivado xsim)
-- "fabric" tc_counter_fabric (runs anywhere, for example GHDL)
-- "infer"  tc_counter_infer  (the USE_DSP inference experiment, runs anywhere)
--
-- Checks:
--   * tc_flag is high in exactly the cycles where count = TC
--   * count returns to zero on the cycle after the match (period TC + 1)
--   * with en low at the terminal count the counter and the flag hold
--   * three matches are seen in the window
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_tc_counter is
  generic (
    VARIANT : string  := "dsp";
    TC      : natural := 9
  );
end entity tb_tc_counter;

architecture sim of tb_tc_counter is

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal en      : std_logic := '0';
  signal count   : std_logic_vector(47 downto 0);
  signal tc_flag : std_logic;
  signal done    : boolean := false;

begin

  clk <= not clk after 5 ns when not done else '0';

  g_dsp : if VARIANT = "dsp" generate
    dut : entity work.tc_counter_dsp
      generic map (TC => TC)
      port map (clk => clk, rst => rst, en => en, count => count, tc_flag => tc_flag);
  end generate g_dsp;

  g_fab : if VARIANT = "fabric" generate
    dut : entity work.tc_counter_fabric
      generic map (TC => TC)
      port map (clk => clk, rst => rst, en => en, count => count, tc_flag => tc_flag);
  end generate g_fab;

  g_inf : if VARIANT = "infer" generate
    dut : entity work.tc_counter_infer
      generic map (TC => TC)
      port map (clk => clk, rst => rst, en => en, count => count, tc_flag => tc_flag);
  end generate g_inf;

  stim : process
    variable cyc      : integer := 0;
    variable matches  : integer := 0;
    variable errors   : integer := 0;
    variable last_tc  : integer := -1;
    variable cnt_i    : integer;
    variable expect   : integer := 1;   -- first sample is taken after one enabled clock

    procedure sample is
    begin
      wait until falling_edge(clk);
      cyc   := cyc + 1;
      cnt_i := to_integer(unsigned(count(30 downto 0)));
      report "cyc " & integer'image(cyc) & "  count " & integer'image(cnt_i)
           & "  tc_flag " & std_logic'image(tc_flag);
      -- flag must agree with the value
      if (tc_flag = '1') /= (cnt_i = TC) then
        report "ERROR: tc_flag " & std_logic'image(tc_flag) & " with count "
             & integer'image(cnt_i) severity error;
        errors := errors + 1;
      end if;
    end procedure sample;
  begin
    -- hold reset for a while (the UNISIM library asserts GSR for the first
    -- 100 ns of simulation, so wait past that before trusting the model)
    wait for 150 ns;
    wait until falling_edge(clk);
    rst <= '0';
    en  <= '1';

    -- free running: expect 1,..,TC,0,1,.. ending on the third match
    for i in 1 to 3 * (TC + 1) - 1 loop
      sample;
      if cnt_i /= expect then
        report "ERROR: expected " & integer'image(expect) severity error;
        errors := errors + 1;
      end if;
      if tc_flag = '1' then
        matches := matches + 1;
        if last_tc >= 0 and cyc - last_tc /= TC + 1 then
          report "ERROR: period " & integer'image(cyc - last_tc) severity error;
          errors := errors + 1;
        end if;
        last_tc := cyc;
      end if;
      if expect = TC then expect := 0; else expect := expect + 1; end if;
    end loop;

    -- now stop the clock enable while sitting on the terminal count
    -- (the loop above ended with count = TC, flag = 1, sampled on the
    -- falling edge, so en goes low before the next rising edge)
    en <= '0';
    for i in 1 to 4 loop
      sample;
      if cnt_i /= TC or tc_flag /= '1' then
        report "ERROR: counter did not hold at the terminal count with en low"
          severity error;
        errors := errors + 1;
      end if;
    end loop;
    -- the first enabled clock performs the automatic reset
    en <= '1';
    sample;
    if cnt_i /= 0 then
      report "ERROR: no reset on the first enabled cycle after the hold" severity error;
      errors := errors + 1;
    end if;

    report "counter: " & integer'image(matches) & " terminal-count matches, period "
         & integer'image(TC + 1) & " and match at count = " & integer'image(TC)
         & ", en hold checked: " & integer'image(errors) & " errors";
    if errors = 0 then
      report "RESULT: PASS";
    else
      report "RESULT: FAIL" severity error;
    end if;
    done <= true;
    wait;
  end process stim;

end architecture sim;
