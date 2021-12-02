// SPDX-License-Identifier: GPL-3.0-only

// Origin Source : https://layerzero.gitbook.io/getting-started/github/interfaces

pragma solidity 0.8.10;

interface ILayerZeroReceiver {
   // the method which your contract needs to implement to receive messages
   function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external;
}
