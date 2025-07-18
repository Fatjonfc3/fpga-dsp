library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- based on this article explanation , really neat approach
--https://wirelesspi.com/mueller-and-muller-timing-synchronization-algorithm

entity error_estimation is
generic
(
data_width : integer := 16;
fixed_point_width : integer := 8;


)
port 
(
	clk , rst , ce : in std_logic;
	data_in : in std_logic_Vector ( data_Width - 1 downto  0 );
	error_estimate : out std_logic_vector ( 2* data_Width - 1 + 1	downto 0)
);
end entity error_estimation;
-- the result width is based on this reasoning
-- we subtract 2 signed numbers , so always + 1 bit, we multiply the estimated symbol value with the current signal , so we maintain the bit width for the estimated symbol, maybe not the best approach but conservative I guess
-- it also depends a lot on the levels of the modulation
-- in this scenario I just considered a pam use case binary +1 or -1
--not so generic, but I will take care about that

architecture rtl of error_estimation is



signal data_in_delayed : signed ( data_Width - 1 downto 0 ):= ( others => '0');
signal estimated_symbol , estimated_symbol_Reg : signed( data_Width - 1 downto 0 ) := ( others => '0');
signal rp_prior_term , rp_posterior_term : signed ( 2* data_Width - 1 + 1 donwto 0 ) := ( others => '0');


begin
estimated_symbol <= to_signed ( -1 , data_width) when data_in( data_in'high) = '1' else
		 to_signed ( 1 , data_width) ;

process ( clk , rst )
begin
if rising_edge ( clk ) then
	if ce = '1' then
		data_in_delayed <= to_signed (data_in);
		estimated_symbol_reg <= estimated_symbol;
	end if;
end if;

ERROR_ESTIMATE : process ( clk , rst)
begin
if rising_edge ( clk ) then
	if ce = '1' then
	-- rp ( -TM + epsilon ) = z ( m - 1 ) * a[m]
	rp_prior_term <= estimated_Symbol *  data_in_Delayed;
	-- rp ( TM + epsilon ) = z ( m  ) * a[m - 1]
	rp_posterior_term <= to_signed ( data_in ) * estimated_symbol_Reg;
	estimated_error <= rp_posterior_term - rp_prior_term;
	--high usage of resources , we could exploit the fact of having a higher speed clk but kind of downsampling using the ce , so to use the same dsp multiplier to calculate the values 
--the schematic at the article helped a lot, always try to draw the design
	end if;
end if;
end process ERROR_ESTIMATE

end process;
