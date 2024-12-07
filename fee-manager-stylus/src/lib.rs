// Allow `cargo stylus export-abi` to generate a main function.
#![cfg_attr(not(feature = "export-abi"), no_main)]
extern crate alloc;

use alloy_primitives::U256;
/// Import items from the SDK. The prelude contains common traits and macros.
use stylus_sdk::{
    alloy_primitives::{B256, I32, U128, U32},
    console,
    prelude::*,
};

// Define some persistent storage using the Solidity ABI.
// `FeeManager` will be the entrypoint.
sol_storage! {
    #[entrypoint]
    pub struct FeeManager  {
        uint256 number;
        mapping(bytes32 => mapping(int32 => TickInfo)) tick_infos;
    }

    pub struct TickInfo {
        bytes32 pool_id;
        int32 tick;
        uint128 liquidity;
        uint32 fee;
    }
}

pub trait IFeeManager {
    fn update_fee_per_tick(
        &mut self,
        pool_id: B256, // Equivalent to bytes32
        liquidity: u128,
        tick_lower: i32,
        tick_upper: i32,
        tick_spacing: u32,
        fee_init: u32,
        fee_max: u32,
    );

    fn get_fee(&self, pool_id: B256, tick: i32) -> u32;

    fn get_fees(&self, num_ticks: u32, fee_init: u32, fee_max: u32) -> Vec<u32>;
}

/// Declare that `FeeManager` is a contract with the following external methods.
#[public]
impl IFeeManager for FeeManager {
    fn get_fee(&self, pool_id: B256, tick: i32) -> u32 {
        let _tick = tick.to_string().parse::<I32>().unwrap();
        self.tick_infos
            .get(pool_id)
            .get(_tick)
            .fee
            .get()
            .to_string()
            .parse::<u32>()
            .unwrap()
    }

    fn update_fee_per_tick(
        &mut self,
        pool_id: B256, // Equivalent to bytes32
        liquidity: u128,
        tick_lower: i32,
        tick_upper: i32,
        tick_spacing: u32,
        fee_init: u32,
        fee_max: u32,
    ) {
        let num_ticks = (tick_upper - tick_lower + 1) as u32;
        let liq_per_tick = U256::from(liquidity / num_ticks as u128);

        let fees_per_ticks = _calc_fees_per_ticks(num_ticks, fee_init, fee_max);

        let mut tick_index = 0;
        let mut current_liq_mut = U256::from(0);
        let fee_max_times_liq_per_tick = U256::from(fee_max) * liq_per_tick;

        for i in (tick_lower..=tick_upper).step_by(tick_spacing.try_into().unwrap()) {
            let tick_signed_32 = i.to_string().parse::<I32>().unwrap();
            let current_liq = U256::from(
                self.tick_infos
                    .get(pool_id)
                    .get(tick_signed_32)
                    .liquidity
                    .get(),
            );
            current_liq_mut += current_liq;
            let fee_per_tick = U256::from(fees_per_ticks[tick_index]);
            let fee_calc = ((fee_per_tick * current_liq) + fee_max_times_liq_per_tick)
                .div_ceil(U256::from(10_000));

            let mut tick_infos_setter = self.tick_infos.setter(pool_id);
            let mut tick_info_setter = tick_infos_setter.setter(tick_signed_32);
            tick_info_setter.pool_id.set(pool_id);
            tick_info_setter.tick.set(tick_signed_32);
            tick_info_setter.fee.set(U32::from(std::cmp::min(
                fee_calc.to_string().parse::<u32>().unwrap(),
                fee_max,
            )));

            tick_info_setter
                .liquidity
                .set(U128::from(current_liq + liq_per_tick));
            tick_index += 1;
        }
    }

    fn get_fees(&self, num_ticks: u32, fee_init: u32, fee_max: u32) -> Vec<u32> {
        _calc_fees_per_ticks(num_ticks, fee_init, fee_max)
    }
}

fn _calc_fees_per_ticks(num_ticks: u32, fee_init: u32, fee_max: u32) -> Vec<u32> {
    let mut fees = vec![0; num_ticks as usize];
    fees[0] = fee_max;
    fees[(num_ticks - 1) as usize] = fee_max;

    if num_ticks % 2 == 0 {
        let tick_fee = fee_max / (1 + (num_ticks - 2) / 2);
        for i in 1..(num_ticks - 1) {
            fees[i as usize] = tick_fee;
        }
    } else {
        let middle = num_ticks / 2;
        fees[middle as usize] = fee_init;

        let fee_inc = (fee_max - fee_init) / (num_ticks - 1) / 2;
        let mut last_fee = fee_init;

        for i in (middle + 1)..(num_ticks - 1) {
            fees[i as usize] = last_fee + fee_inc;
            last_fee = fees[i as usize];
        }

        last_fee = fee_init;
        for i in (1..middle).rev() {
            fees[i as usize] = last_fee + fee_inc;
            last_fee = fees[i as usize];
        }
    }

    fees
}
