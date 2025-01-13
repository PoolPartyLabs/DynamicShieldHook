// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface Errors {
    // aderyn-ignore-next-line(useless-error)
    error PoolPositionAlreadyClosed();

    // aderyn-ignore-next-line(useless-error)
    error PoolPositionPaused();

    // aderyn-ignore-next-line(useless-error)
    error PoolPositionNotFound();

    // aderyn-ignore-next-line(useless-error)
    error PoolNotInitialized();

    // aderyn-ignore-next-line(useless-error)
    error PoolPositionMovingRange();

    // aderyn-ignore-next-line(useless-error)
    error PoolPositionNameExists();

    // aderyn-ignore-next-line(useless-error)
    error PoolPositionNotClosed();

    // aderyn-ignore-next-line(useless-error)
    error PoolPositionHasYetLiquidityAfterClose();

    // aderyn-ignore-next-line(useless-error)
    error Unauthorized();

    // aderyn-ignore-next-line(useless-error)
    error AddressIsZero();

    // aderyn-ignore-next-line(useless-error)
    error MaxInvestmentExceeded();

    // aderyn-ignore-next-line(useless-error)
    error MinInvestmentNotMet();

    // aderyn-ignore-next-line(useless-error)
    error IsDestroyed();

    // aderyn-ignore-next-line(useless-error)
    error NoRewardsToCollect();

    // aderyn-ignore-next-line(useless-error)
    error TooManyPositions(uint256 max, uint256 current);

    // aderyn-ignore-next-line(useless-error)
    error NotPositionOperator();

    // aderyn-ignore-next-line(useless-error)
    error OperatorNotWhitelisted();

    // aderyn-ignore-next-line(useless-error)
    error OnlyOperatorCanClosePosition();

    // aderyn-ignore-next-line(useless-error)
    error PermitBatchInvalid();

    // aderyn-ignore-next-line(useless-error)
    error PermitSpenderInvalid();

    // aderyn-ignore-next-line(useless-error)
    error Cube3ProtectionEnabled();

    // aderyn-ignore-next-line(useless-error)
    error Cube3ProtectionNotEnabled();

    // aderyn-ignore-next-line(useless-error)
    error ProtectionEnabled();

    // aderyn-ignore-next-line(useless-error)
    error ProtectionNotEnabled();

    // aderyn-ignore-next-line(useless-error)
    error SignatureExpired();

    // aderyn-ignore-next-line(useless-error)
    error SignatureAlreadyUsed();

    // aderyn-ignore-next-line(useless-error)
    error ExpiredDeadline();

    // aderyn-ignore-next-line(useless-error)
    error MissingMultihopSwapPath();

    // aderyn-ignore-next-line(useless-error)
    error MissingMultihopSwapPathForCurrency0();

    // aderyn-ignore-next-line(useless-error)
    error MissingMultihopSwapPathForCurrency1();

    // aderyn-ignore-next-line(useless-error)
    error IsNotStableCurrency();

    // aderyn-ignore-next-line(useless-error)
    error StableCurrencyAmountCannotBeZero(uint256 amount0, uint256 amount1);

    // aderyn-ignore-next-line(useless-error)
    error CurrencyAmountCannotBeZero(uint256 amount0, uint256 amount1);

    // aderyn-ignore-next-line(useless-error)
    error CurrencyMustNotBeZero(address currency0, address currency1);

    // aderyn-ignore-next-line(useless-error)
    error CurrencyMustNotBeEqual(address currency0, address currency1);

    // aderyn-ignore-next-line(useless-error)
    error InvalidLiquidityAmounts();

    // aderyn-ignore-next-line(useless-error)
    error InvalidFee(uint24 fee);

    // aderyn-ignore-next-line(useless-error)
    error InvalidOperatorFee(uint24 fee);

    // aderyn-ignore-next-line(useless-error)
    error InvalidProtocolFee(uint24 fee);

    // aderyn-ignore-next-line(useless-error)
    error InvalidRemovePercentage(uint256 removePercentage);

    // aderyn-ignore-next-line(useless-error)
    error RemovePercentageTooHigh(uint256 removePercentage);

    // aderyn-ignore-next-line(useless-error)
    error InvestorHasNoLiquidity();

    // aderyn-ignore-next-line(useless-error)
    error InvestorMustNotBeOperator();

    // aderyn-ignore-next-line(useless-error)
    error TickLowerMustBeLessThanTickUpper(int24 tickLower, int24 tickUpper);

    // aderyn-ignore-next-line(useless-error)
    error TicksMustBeWithinBounds(int24 tickLower, int24 tickUpper);

    // aderyn-ignore-next-line(useless-error)
    error InsuficientFees(
        uint256 fee0,
        uint256 amount0,
        uint256 fee1,
        uint256 amount1
    );

    // aderyn-ignore-next-line(useless-error)
    error InsuficientStableFee(uint256 fee, uint256 amount);

    // aderyn-ignore-next-line(useless-error)
    error NotWETH9OrManager(address sender);

    // aderyn-ignore-next-line(useless-error)
    error VaultsAndSnapshotManagersAlreadySet();
}
