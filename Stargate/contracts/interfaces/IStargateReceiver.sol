// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

interface IStargateReceiver {
    function sgReceive(
        uint16 _chainId, 
        bytes memory _srcAddress, 
        uint _nonce, 
        address _token, 
        uint amountLD, 
        bytes memory payload
    ) external;
}
