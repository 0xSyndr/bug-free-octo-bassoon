// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";
import "./LayerZero/ILayerZeroReceiver.sol";
// import "./IERC2612.sol";

interface IDToken is ILayerZeroReceiver, IERC20Metadata { 
    // --- Functions ---

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;

    function sendTokens(
        uint16 _chainId,                            // send tokens to this chainId
        bytes calldata _dstMultiChainTokenAddr,     // destination address of MultiChainToken
        uint _qty                                   // how many tokens to send
    ) external payable;

    // function sendToPool(address _sender,  address poolAddress, uint256 _amount) external;

    // function returnFromPool(address poolAddress, address user, uint256 _amount ) external;
}
