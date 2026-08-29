-- ================================================================================ --
-- NEORV32 - Test Setup Using The UART-Bootloader To Upload And Run Executables     --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

library accelerator;
use accelerator.systolic_pkg.all;

entity neorv32_test_setup_bootloader is
  generic (
    -- adapt these for your setup --
    CLOCK_FREQUENCY : natural := 18000000;  -- clock frequency of clk_i in Hz
    IMEM_SIZE       : natural := 8*1024;   -- size of processor-internal instruction memory in bytes
    DMEM_SIZE       : natural := 16*1024    -- size of processor-internal data memory in bytes
  );
  port (
    -- Global control --
    clk_i       : in  std_ulogic; -- global clock, rising edge
    rstn_i      : in  std_ulogic; -- global reset, low-active, async

    -- GPIO --
    gpio_o : out std_ulogic_vector(5 downto 0); -- parallel output

    -- UART0 --
    uart0_txd_o : out std_ulogic; -- UART0 send data
    uart0_rxd_i : in  std_ulogic  -- UART0 receive data
  );
end entity;

architecture neorv32_test_setup_bootloader_rtl of neorv32_test_setup_bootloader is

  signal con_gpio_out : std_ulogic_vector(31 downto 0);

  ----------------------------------------------------------------------------------------------
  -- ACCELERATOR DEDICATED
  ----------------------------------------------------------------------------------------------

  -- SLINK --
  type slink_t is record
    data  : std_ulogic_vector(31 downto 0);
    valid : std_ulogic;
    ready : std_ulogic;
  end record;

  signal slink_tx, slink_rx : slink_t;

  -- CFS --
  signal cfs_in    : std_ulogic_vector(255 downto 0);
  signal cfs_out   : std_ulogic_vector(255 downto 0);
  signal acc_ready : std_ulogic;

  -- Accelerator interface conversion signals --
  signal acc_num     : std_logic_vector(31 downto 0);
  signal acc_tx_data : std_logic_vector(31 downto 0);
  signal acc_rx_data : std_logic_vector(31 downto 0);

begin

  ----------------------------------------------------------------------------------------------
  -- ACCELERATOR / NEORV32 INTERFACE CONVERSIONS
  ----------------------------------------------------------------------------------------------

  cfs_in <= (0 => acc_ready, others => '0');

  acc_num     <= std_logic_vector(cfs_out(32 downto 1));
  acc_tx_data <= std_logic_vector(slink_tx.data);

  slink_rx.data <= std_ulogic_vector(acc_rx_data);

  -- The Core Of The Problem ----------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  neorv32_top_inst : neorv32_top
  generic map (
    -- Clocking --
    CLOCK_FREQUENCY  => CLOCK_FREQUENCY,

    -- Boot Configuration --
    BOOT_MODE_SELECT => 2,

    -- RISC-V CPU Extensions --
    RISCV_ISA_C      => true,
    RISCV_ISA_M      => true,
    RISCV_ISA_Zicntr => true,

    -- Internal Instruction memory --
    IMEM_EN          => true,
    IMEM_SIZE        => IMEM_SIZE,

    -- Internal Data memory --
    DMEM_EN          => true,
    DMEM_SIZE        => DMEM_SIZE,

    -- Processor peripherals --
    IO_GPIO_NUM      => 6,
    IO_CLINT_EN      => true,
    IO_UART0_EN      => true,

    -- Custom Functions Subsystem --
    IO_CFS_EN        => true,

    -- Stream Link Interface --
    IO_SLINK_EN      => true,
    IO_SLINK_RX_FIFO => 16,
    IO_SLINK_TX_FIFO => 8
  )
  port map (
    -- Global control --
    clk_i       => clk_i,
    rstn_i      => rstn_i,

    -- GPIO --
    gpio_o      => con_gpio_out,

    -- primary UART0 --
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,

    -- Stream Link Interface --
    slink_rx_dat_i => slink_rx.data,
    slink_rx_val_i => slink_rx.valid,
    slink_rx_rdy_o => slink_rx.ready,

    slink_tx_dat_o => slink_tx.data,
    slink_tx_val_o => slink_tx.valid,
    slink_tx_rdy_i => slink_tx.ready,

    -- Custom Functions Subsystem IO --
    cfs_in_i  => cfs_in,
    cfs_out_o => cfs_out
  );

  -----------------------------------------------------------------
  -- ACCELERATOR INSTANTIATION
  -----------------------------------------------------------------
  my_acc_inst : entity accelerator.acc_top
    port map (
      start_i   => cfs_out(0),
      clk_i     => clk_i,
      rstn_i    => rstn_i,
      acc_num_i => acc_num,

      tx_vld_i  => slink_tx.valid,
      rx_rdy_i  => slink_rx.ready,
      tx_data_i => acc_tx_data,

      tx_rdy_o  => slink_tx.ready,
      rx_vld_o  => slink_rx.valid,
      rdy_o     => acc_ready,
      rx_data_o => acc_rx_data
    );

  -- GPIO output --
  gpio_o <= con_gpio_out(5 downto 0);

end architecture;