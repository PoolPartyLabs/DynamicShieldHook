// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";

contract PoolVaultManager {
    using PoolIdLibrary for PoolKey;

    address private s_hook;

    mapping(PoolId poolId => Position) private postions;
    IPositionManager s_lpm;

    error InvalidPositionManager();
    error InvalidHook();
    error InvalidSelf();

    struct Position {
        PoolKey key;
        address owner;
        uint256 tokenId;
    }

    struct CallData {
        PoolKey key;
        address owner;
    }

    constructor(address _hook,IPositionManager _lpm)  {
        s_hook = _hook;
        s_lpm = _lpm;
    }

    function depositPosition(PoolKey calldata _key, uint256 _tokenId, address _owner) public payable {
        IERC721(address(s_lpm)).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId,
            abi.encode(CallData({key: _key, owner: _owner}))
        ); 
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        // Check if the sender is the hook
        if (msg.sender != address(s_lpm)) revert InvalidPositionManager();
        if (_from != s_hook) revert InvalidHook();
        if (_operator != address(this)) revert InvalidSelf();

        CallData memory data = abi.decode(_data, (CallData));
        postions[data.key.toId()] = Position(data.key, data.owner, _tokenId);

        return this.onERC721Received.selector;
    }
}
