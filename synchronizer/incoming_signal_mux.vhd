library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity incoming_signal_mux is
generic (
	DATA_WIDTH : integer : 16;
)
port (
	clk , rst , ce : in std_logic;
	data_in : in std_logic_vector ( DATA_WIDTH - 1 downto 0 );
	data_out : out std_logic_Vector ( data_width - 1 downto 0)
)
end entity; 


architecture rtl of incoming_signal_mux is

signal data_out_next , data_out_Reg : std_logic_vector ( data_width - 1 downto 0) := ( others => '0');
begin

data_out_next <= data_in when ce = '1' else
	    data_out_reg; -- TO NOT INFER A LATCH , maybe just hallucination but not sure if there may be a small glitch;
--used this approach just to avoid a clock delay if we just used a clocked process so just a ff with ce , maybe it would also be cheaper since Xilinx fpga already have ff with clock enable if im not wrong

data_out <= data_out_next ; --just a wire
process ( clk , rst  )
if rising_Edge ( clk ) then
	data_out_Reg <= data_out_next; 
end if;
end process;



end architecture rtl;
