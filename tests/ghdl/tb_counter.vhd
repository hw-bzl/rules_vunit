library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_counter is
    generic (runner_cfg : string);
end entity tb_counter;

architecture tb of tb_counter is
    constant clk_period : time := 10 ns;

    signal clk    : std_logic := '0';
    signal rst    : std_logic := '1';
    signal enable : std_logic := '0';
    signal count  : std_logic_vector(7 downto 0);
begin
    dut : entity work.counter
        port map (
            clk    => clk,
            rst    => rst,
            enable => enable,
            count  => count
        );

    clk <= not clk after clk_period / 2;

    main : process
    begin
        test_runner_setup(runner, runner_cfg);

        -- Hold reset for two clocks across every test.
        rst    <= '1';
        enable <= '0';
        wait for clk_period * 2;
        rst    <= '0';

        while test_suite loop
            if run("test_resets_to_zero") then
                wait for clk_period;
                check_equal(unsigned(count), to_unsigned(0, 8), "counter idle after reset");

            elsif run("test_counts_when_enabled") then
                enable <= '1';
                wait for clk_period * 5;
                enable <= '0';
                wait for clk_period;
                -- 5 enabled clock edges → count == 5
                check_equal(unsigned(count), to_unsigned(5, 8), "counter advanced 5 ticks");

            elsif run("test_hold_when_disabled") then
                enable <= '1';
                wait for clk_period * 3;
                enable <= '0';
                wait for clk_period * 5;
                check_equal(unsigned(count), to_unsigned(3, 8), "counter held at 3");
            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;
end architecture tb;
