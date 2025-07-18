library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ce_generator is
generic (
	CE_PER_CLK : integer := 32;

)
port (
	clk , rst : in std_logic;
	ce : out std_logic

);

architecture rtl of ce_generator is

--signal counter : unsigned ( 4 downto 0) := ( OTHERS => '0');
signal counter : unsigned ( to_integer ( ceil ( log2 ( CE_PER_CLK))) - 1 downto 0) := ( others => '0');
signal ce_reg : std_logic := '0'; 
begin

process ( clk , rst )
begin
if rising_Edge ( clk ) then
	if rst  = '1' then
		ce_reg <= '0';
		counter <= ( others => '0');
	else 
		counter <= counter + 1;
		if counter = CE_PER_CLK - 1 then
			ce_reg <= '1';
			counter <= ( others => '0');
		end if;
	end if;
end if;
end process;
--used a sync reset just for ease
--we could also use an async assert sync deassertion
--if rst ='1' then
--rst_reg_1 <= '1';
--rst_reg_2 <= '1';
--else if rising_Edge ( clk )
--rst_reg_1 <= rst;
--rst_reg_2 <= rst_Reg_1;
--end process;
ce <= ce_reg;


end architecture rtl;
