// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WithdrawPosition} from "./library/WithdrawPosition.sol";
import {MintPosition} from "./library/MintPosition.sol";
import {Liquidity} from "./library/Liquidity.sol";
import {CollectFees} from "./library/CollectFees.sol";
import {ClosePosition} from "./library/ClosePosition.sol";
import "./interfaces/Constants.sol";
import "./Base.sol";

/**
 * @title PoolPartyPosition contract
 * @author Pool Party
 * @notice This is used to create and manage a Uniswap V3 pool position for a group of investors.
 * When a pool position is created, the operator is the owner of the pool position and
 * the operator/investor can add or remove liquidity from the pool position.
 * The operator/investor can also collect rewards from the pool position based on the amount of liquidity they have in the pool position.
 */
// aderyn-ignore-next-line(contract-locks-ether)
contract PoolPartyPosition is Base {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPoolPartyPosition
    function mintPosition(
        MintPositionParams memory _params
    )
        external
        payable
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
        returns (
            PositionId positionId,
            uint256 _tokenId,
            uint128 _liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // slither-disable-start unused-return
        return MintPosition.mintPosition(s, this, address(this), _params);
        // slither-disable-end unused-return
    }

    /// @inheritdoc IPoolPartyPosition
    function increaseLiquidity(
        IncreaseLiquidityParams calldata _params
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
        returns (uint128 _liquidity, uint256 amount0, uint256 amount1)
    {
        // slither-disable-start unused-return
        return Liquidity.increaseLiquidity(s, this, _params);
        // slither-disable-end unused-return
    }

    /// @inheritdoc IPoolPartyPosition
    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function decreaseLiquidity(
        DecreaseLiquidityParams calldata _params
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
        returns (uint128, uint256, uint256)
    {
        // slither-disable-start unused-return
        return Liquidity.decreaseLiquidity(s, this, _params);
        // slither-disable-end unused-return
    }

    /// @inheritdoc IPoolPartyPosition
    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function collect(
        CollectParams calldata _params
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
        returns (uint256 earned0, uint256 earned1)
    {
        // slither-disable-start unused-return
        return CollectFees.collect(s, this, _params);
        // slither-disable-end unused-return
    }

    /// @inheritdoc IPoolPartyPosition
    function withdraw(
        WithdrawParams calldata _params
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
        returns (uint256, uint256, uint256, uint256)
    {
        // slither-disable-start unused-return
        return WithdrawPosition.withdraw(s, this, _params);
        // slither-disable-end unused-return
    }

    /// @inheritdoc IPoolPartyPosition
    function closePosition(
        ClosePositionParams calldata _params
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // slither-disable-start unused-return
        return ClosePosition.closePosition(s, this, _params);
        // slither-disable-end unused-return
    }

    function moveRange(
        MoveRangeParams calldata
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE) // aderyn-ignore(centralization-risk)
        whenManagerNotDestroyed
        whenManagerNotPaused
        whenNotMovingRange
    {
        revert("Not implemented");
    }

    // slither-disable-start dead-code
    ///@dev required by the OZ UUPS module
    // aderyn-ignore-next-line(empty-block)
    function _authorizeUpgrade(
        address
    )
        internal
        override
        whenManagerNotDestroyed
        onlyRole(UPGRADER_ROLE) // aderyn-ignore(centralization-risk)
    {}

    // slither-disable-end dead-code

    receive() external payable {
        require(
            msg.sender == s.i_WETH9 || msg.sender == s.i_manager,
            Errors.NotWETH9OrManager(msg.sender)
        );
    }

    fallback() external payable {
        require(
            msg.sender == s.i_WETH9 || msg.sender == s.i_manager,
            Errors.NotWETH9OrManager(msg.sender)
        );
    }
}
