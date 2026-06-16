library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_adder is
    generic (runner_cfg : string);
end entity tb_adder;

architecture tb of tb_adder is
    signal x         : std_logic_vector(7 downto 0) := (others => '0');
    signal y         : std_logic_vector(7 downto 0) := (others => '0');
    signal carry_in  : std_logic := '0';
    signal sum       : std_logic_vector(7 downto 0);
    signal carry_out : std_logic;
begin
    dut : entity work.adder
        port map (
            x                => x,
            y                => y,
            carry_in         => carry_in,
            sum              => sum,
            carry_output_bit => carry_out
        );

    main : process
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            if run("test_basic_add") then
                x        <= x"03";
                y        <= x"04";
                carry_in <= '0';
                wait for 1 ns;
                check_equal(sum, std_logic_vector'(x"07"), "3 + 4 = 7");
                check_equal(carry_out, '0', "no carry expected");

            elsif run("test_with_carry_in") then
                x        <= x"10";
                y        <= x"20";
                carry_in <= '1';
                wait for 1 ns;
                check_equal(sum, std_logic_vector'(x"31"), "0x10 + 0x20 + 1 = 0x31");
                check_equal(carry_out, '0', "no overflow expected");

            elsif run("test_overflow") then
                x        <= x"FF";
                y        <= x"01";
                carry_in <= '0';
                wait for 1 ns;
                check_equal(sum, std_logic_vector'(x"00"), "0xFF + 1 = 0x00 (wraps)");
                check_equal(carry_out, '1', "carry out expected");
            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;
end architecture tb;
