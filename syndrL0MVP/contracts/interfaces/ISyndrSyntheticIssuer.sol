// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ISyndrSyntheticIssuer {

	// --- L0 Stargate functions ---
    function sgReceive(
        uint16 _chainId, 
        bytes memory _srcAddress, 
        uint _nonce, 
        address _token, 
        uint amountLD, 
        bytes memory payload
    ) external;
}
