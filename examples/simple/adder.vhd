library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder is
    port (
        x                : in  std_logic_vector(7 downto 0);
        y                : in  std_logic_vector(7 downto 0);
        carry_in         : in  std_logic;
        sum              : out std_logic_vector(7 downto 0);
        carry_output_bit : out std_logic
    );
end entity adder;

architecture rtl of adder is
    signal result : unsigned(8 downto 0);
    signal cin_u  : unsigned(8 downto 0);
begin
    cin_u  <= (0 => carry_in, others => '0');
    result <= ('0' & unsigned(x)) + ('0' & unsigned(y)) + cin_u;

    sum              <= std_logic_vector(result(7 downto 0));
    carry_output_bit <= result(8);
end architecture rtl;
