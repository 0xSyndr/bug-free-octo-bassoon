// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./libs/access/Ownable.sol";
import "./libs/token/SafeERC20.sol";
import "./libs/security/ReentrancyGuard.sol";
import "./interfaces/IDToken.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISyndrSyntheticIssuer.sol";

contract SyndrSyntheticIssuer is ISyndrSyntheticIssuer, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string constant public dToken = "dETH";

    bool public vaultOpen;
    uint public dTokenDebt;
    uint public daiColl;
    address public vaultOwner;

    IERC20 public dai;
    IDToken public dETH;

    // stargate router address
    address public stargateRouter;

    uint constant public DECIMAL_PRECISION = 1e18;

    uint constant public _100pct = 1000000000000000000;

	// Minimum collateral ratio for individual asset vaults
    uint constant public MCR = 1100000000000000000; // 110%

    uint constant public ETH_PRICE = 4000 * DECIMAL_PRECISION;
    uint constant public DAI_PRICE = 1 * DECIMAL_PRECISION; 

    // maps l0 chainId => contractAddress => bool
    // tracks which addresses have added whitelisted and have authority to call 
    // sgReceive function on this contracts for each l0 chainId
    mapping(uint16 => mapping(address => bool)) public whitelistedCallerContracts;

    enum SgOpcodes {
        openVault,
        addCollateral,
        withdrawCollateral,
        withdrawDTokens,
        repayDTokens,
        closeVault,
        redeemDTokens
    }
    
    // struct for sgReceive
    struct SgReceiveParams {
        SgOpcodes opcode; 
        uint dETHDebt;
        uint daiCollAmt;
        // this must only be a non-contract owner!?
        // !! LOTS OF ATTACK VECTORS here !!!!!!
        address vaultOwner;
        uint srcChainId;
    }

    constructor(address _daiAddress, address _dETHAddress, address _stargateRouter) {
        dai = IERC20(_daiAddress);
        dETH = IDToken(_dETHAddress);
        stargateRouter = _stargateRouter;
        vaultOpen = false;
    }

    function whitelist(address _addr, uint16 _chainId) external onlyOwner {
        whitelistedCallerContracts[_chainId][_addr] = true;
    }

    function blacklist(address _addr, uint16 _chainId) external onlyOwner {
        whitelistedCallerContracts[_chainId][_addr] = false;
    }

    function openVault(uint dETHDebt, uint daiCollAmt) public {
        _openVault(dETHDebt, daiCollAmt, msg.sender);
    }

    function addCollateral(uint daiCollAmt) public {
        _addCollateral(daiCollAmt, msg.sender);
    }

    function withdrawCollateral(uint daiCollAmt) public {
        _withdrawCollateral(daiCollAmt, msg.sender);
    }



    function withdrawDToken(uint dETHAmount) public {
        _withdrawDToken(dETHAmount, msg.sender);
    }


    function repayDToken(uint dETHAmount) public {
        _repayDToken(dETHAmount, msg.sender);
    }

    function closeVault() public {
        _closeVault(msg.sender);
    }

    function _openVault(uint dETHDebt, uint daiCollAmt, address _vaultOwner) internal {
        require(!vaultOpen, "dEth Vault already open");
        
        uint vaultCR = (daiCollAmt * DAI_PRICE) / (dETHDebt * ETH_PRICE);
        require(vaultCR >= MCR, "SSI: cannot open vault below with a CR below 110%");

        // update vars
        vaultOpen = true;
        dTokenDebt = dETHDebt;
        daiColl = daiCollAmt;
        vaultOwner = _vaultOwner;

        // transfer coll
        dai.safeTransferFrom(_vaultOwner, address(this), daiCollAmt);

        // mint dETH
        dETH.mint(_vaultOwner, dETHDebt);
    }

    function _addCollateral(uint daiCollAmt,address _vaultOwner) public {
        require(vaultOpen, "dEth Vault is not open");
        require(_vaultOwner == vaultOwner, "SSI: caller must be vault owner");

        uint newVaultCR = ((daiCollAmt + daiColl) * DAI_PRICE) / (dTokenDebt * ETH_PRICE);
        require(newVaultCR >= MCR, "SSI: vault cr below 110%");

        daiColl = daiCollAmt + daiColl;

        dai.safeTransferFrom(_vaultOwner, address(this), daiCollAmt);
    }

    function _withdrawCollateral(uint daiCollAmt, address _vaultOwner) public {
        require(vaultOpen, "dEth Vault is not open");
        require(_vaultOwner == vaultOwner, "SSI: caller must be vault owner");
        require(daiCollAmt < daiColl, "Cannot withdraw more than the vault balance");

        uint newVaultCR = ((daiColl - daiCollAmt) * DAI_PRICE) / (dTokenDebt * ETH_PRICE);
        require(newVaultCR >= MCR, "SSI: withdraw cannot leave vault CR below 110%");

        daiColl = daiColl - daiCollAmt;

        // transfer dai coll from this contract to caller
        dai.safeTransfer(_vaultOwner, daiCollAmt);
    }

    function _withdrawDToken(uint dETHAmount, address _vaultOwner) public {
        require(vaultOpen, "dEth Vault is not open");
        require(_vaultOwner == vaultOwner, "SSI: caller must be vault owner");

        uint newVaultCR = ((daiColl) * DAI_PRICE) / ((dTokenDebt + dETHAmount) * ETH_PRICE);
        require(newVaultCR >= MCR, "SSI: withdraw cannot leave vault CR below 110%");

        dTokenDebt = dTokenDebt + dETHAmount;
        // mint dETH
        dETH.mint(_vaultOwner, dETHAmount);
    }

    function _repayDToken(uint dETHAmount, address _vaultOwner) public {
        require(vaultOpen, "dEth Vault is not open");
        require(_vaultOwner == vaultOwner, "SSI: caller must be vault owner");
        require(dETHAmount < dTokenDebt, "Cannot repay more what has been borrowed");

        uint newVaultCR = ((daiColl) * DAI_PRICE) / ((dTokenDebt - dETHAmount) * ETH_PRICE);
        require(newVaultCR >= MCR, "SSI: withdraw cannot leave vault CR below 110%");

        dTokenDebt = dTokenDebt - dETHAmount;
        // burn dETH from caller's a/c
        dETH.burn(_vaultOwner, dETHAmount);
    }

    function _closeVault(address _vaultOwner) internal {
        require(vaultOpen, "dEth Vault is not open");
        require(_vaultOwner == vaultOwner, "SSI: caller must be vault owner");
        
        uint vaultCR = (daiColl * DAI_PRICE) / (dTokenDebt * ETH_PRICE);
        require(vaultCR >= MCR, "SSI: cannot close vault if MCR is below 110%");

        // burn dETH
        dETH.burn(_vaultOwner, dTokenDebt);
        // return collateral to vault owner
        dai.safeTransfer(_vaultOwner, daiColl);
    }

    //-----------------------------------------------------------------------------------------------------------------------
    // STARGATE RECEIVER - the destination contract must implement this function to receive the tokens and payload
    function sgReceive(uint16 _chainId, bytes memory _srcAddress, uint , address _token, uint amountLD, bytes memory payload) override external nonReentrant {
        require(msg.sender == address(stargateRouter), "only stargate router can call sgReceive");
        require(_token == address(dai), "SSI: only supports dai as coll");

        address srcAddress;
        assembly { 
            srcAddress := mload(add(_srcAddress, 20))
        }

        (SgReceiveParams memory params) = abi.decode(payload, (SgReceiveParams));

        require(isValidSgOwner(params.vaultOwner, _chainId, srcAddress) == true, "Invalid Caller");

        // Re-entrancy guard ?? Lots of attack vectors below !!!!!!!!
        // better arch!??
        IERC20(_token).safeTransfer(params.vaultOwner, amountLD);

        if (params.opcode == SgOpcodes.openVault) {
            _openVault(params.dETHDebt, params.daiCollAmt, params.vaultOwner);
        } else if (params.opcode == SgOpcodes.addCollateral) {
            _addCollateral(params.daiCollAmt, params.vaultOwner);
        } else if (params.opcode == SgOpcodes.withdrawCollateral) {
            _withdrawCollateral(params.daiCollAmt, params.vaultOwner);
        } else if (params.opcode == SgOpcodes.withdrawDTokens) {
            _withdrawDToken(params.dETHDebt, params.vaultOwner);
        } else if (params.opcode == SgOpcodes.repayDTokens) {
            _repayDToken(params.dETHDebt, params.vaultOwner);
        } else if (params.opcode == SgOpcodes.closeVault) {
            _closeVault(params.vaultOwner);
        } else if (params.opcode == SgOpcodes.redeemDTokens) {
            revert();
        } else {
            revert();
        }
    }

    function isValidSgOwner(address _vaultOwner, uint16 _chainId, address _srcAddress) internal view returns(bool) {
        return whitelistedCallerContracts[_chainId][_srcAddress] && _vaultOwner == vaultOwner;
    }
}