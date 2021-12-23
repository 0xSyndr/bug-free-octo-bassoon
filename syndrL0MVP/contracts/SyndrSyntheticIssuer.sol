// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./interfaces/ISyndrSyntheticIssuer.sol";
import "./interfaces/IERC20.sol";

contract SyndrSyntheticIssuer is ISyndrSyntheticIssuer {
    string constant public dToken = "dETH";

    bool public vaultOpen;
    uint public dTokenDebt;
    uint public daiColl;

    IERC20 public dai;

    uint constant public DECIMAL_PRECISION = 1e18;

    uint constant public _100pct = 1000000000000000000;

	// Minimum collateral ratio for individual asset vaults
    uint constant public MCR = 1100000000000000000; // 110%

    uint constant public ETH_PRICE = 4000 * DECIMAL_PRECISION;
    uint constant public DAI_PRICE = 1 * DECIMAL_PRECISION; 

    constructor(address _daiAddress) {
        dai = IERC20(_daiAddress);
    }

    function openVault(uint dETHDebt, uint daiCollAmt) public {
        require(!vaultOpen, "dEth Vault already open");

        // update vars
        uint vaultCR = (daiCollAmt * DAI_PRICE) / dETHDebt * ETH_PRICE;
        require(vaultCR >= MCR, "SSI: cannot open vault below with a CR below 110%");

        // transfer coll
        // transfer _asset _amount from _user to pool
        IERC20(daiAddress).safeTransferFrom(msg.sender, address(this), daiCollAmt);

        // mint dETH
    }

    //-----------------------------------------------------------------------------------------------------------------------
    // STARGATE RECEIVER - the destination contract must implement this function to receive the tokens and payload
    function sgReceive(uint16 _chainId, bytes memory _srcAddress, uint _nonce, address _token, uint amountLD, bytes memory payload) override external {
        // TO-DO
        revert();
    }
}