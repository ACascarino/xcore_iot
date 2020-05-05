// Copyright (c) 2019, XMOS Ltd, All rights reserved

#include <platform.h>
#include <timer.h>
#include <string.h>

#include "soc.h"
#include "xassert.h"
#include "spi_master_dev.h"

static void spi_test_fast_handler(
        soc_peripheral_t peripheral,
        chanend ?data_to_dma_c,
        chanend ?data_from_dma_c,
        chanend ?ctrl_c,
        spi_fast_ports &spi_ctx)
{
    uint8_t data_buf[SPICONF_BUFFER_LEN];
    int tx_len;
    uint32_t cmd;

    size_t rx_len = 0;

    while (1) {
        if (peripheral != NULL) {
            /* Check that a valid buffer was set */
            if ((tx_len = soc_peripheral_rx_dma_direct_xfer(peripheral, data_buf, SPICONF_BUFFER_LEN)) >= 0) {

                int transfer_len;

                if (rx_len > tx_len) {
                    transfer_len = rx_len;
                    memset(data_buf + tx_len, SPICONF_RX_ONLY_CHAR, rx_len - tx_len);
                } else {
                    transfer_len = tx_len;
                }

                spi_fast(transfer_len, data_buf, spi_ctx, rx_len > 0 ? SPI_READ_WRITE : SPI_WRITE);

                if (rx_len > 0) { /* Send response if it had been requested */
                    soc_peripheral_tx_dma_direct_xfer(
                            peripheral,
                            data_buf,
                            rx_len);

                    rx_len = 0;
                }
            }
        }

        select {
        case !isnull(ctrl_c) => soc_peripheral_function_code_rx(ctrl_c, &cmd):
            switch (cmd) {
            case SOC_PERIPHERAL_DMA_TX:
                /*
                 * The application has added a new DMA TX buffer. This
                 * ensures that this select statement wakes up and gets
                 * the TX data in the code above.
                 */
                break;
            case SPI_MASTER_DEV_INIT:
                soc_peripheral_varlist_rx(
                        ctrl_c, 6,
                        sizeof(unsigned), &spi_ctx.cpol,
                        sizeof(unsigned), &spi_ctx.cpha,
                        sizeof(unsigned), &spi_ctx.clock_divide,
                        sizeof(unsigned), &spi_ctx.cs_to_data_delay_ns,
                        sizeof(unsigned), &spi_ctx.byte_setup_ns,
                        sizeof(unsigned), &spi_ctx.data_to_cs_delay_ns);

                spi_fast_init(spi_ctx);
                break;

            case SPI_MASTER_DEV_TRANSACTION:
                soc_peripheral_varlist_rx(
                        ctrl_c, 1,
                        sizeof(size_t), &rx_len);
                break;

            default:
                /* Command is not valid */
                fail("Invalid cmd");
                break;
            }
            break;

        case !isnull(data_from_dma_c) => soc_peripheral_rx_dma_ready(data_from_dma_c):
            /* Check that a valid buffer was set */
            if ((tx_len = soc_peripheral_rx_dma_xfer(data_from_dma_c, data_buf, SPICONF_BUFFER_LEN)) >= 0) {

                int transfer_len;

                if (rx_len > tx_len) {
                    transfer_len = rx_len;
                    memset(data_buf + tx_len, SPICONF_RX_ONLY_CHAR, rx_len - tx_len);
                } else {
                    transfer_len = tx_len;
                }

                spi_fast(transfer_len, data_buf, spi_ctx, rx_len > 0 ? SPI_READ_WRITE : SPI_WRITE);

                if (rx_len > 0) { /* Send response if it had been requested */
                    if (!isnull(data_to_dma_c)) {
                        soc_peripheral_tx_dma_xfer(
                                data_to_dma_c,
                                data_buf,
                                rx_len);
                    }

                    rx_len = 0;
                }
            }
            break;

        }
    }
}

void spi_master_dev(
        soc_peripheral_t peripheral,
        chanend ?data_to_dma_c,
        chanend ?data_from_dma_c,
        chanend ?ctrl_c,
        spi_fast_ports &spi_ctx)
{
    par {
        spi_test_fast_handler(peripheral,
                              data_to_dma_c, data_from_dma_c, ctrl_c,
                              spi_ctx);
    }
}
