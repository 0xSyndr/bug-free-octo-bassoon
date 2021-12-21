// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "./libs/math/SafeMath.sol";
import "./libs/access/Ownable.sol";
import "./interfaces/IStargateReceiver.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract StargateComposed is Ownable, IStargateReceiver {
    using SafeMath for uint256;

    address public stargateRouter;      // stargate router address 
    address public ammRouter;           // amm router (ie: sushiswap, uniswap, etc...)

    // special token value that indicates the sgReceive() should swap OUT native asset
    address public OUT_TO_NATIVE = 0x0000000000000000000000000000000000000000;

    event ReceivedOnDestination(address token, uint qty);

    constructor(address _stargateRouter, address _ammRouter) public {
        stargateRouter = _stargateRouter;
        ammRouter = _ammRouter;
    }

    // 1. swap native on source chain to native on destination chain (!)
    function swapNativeForNative(
        uint16 destChainId,                     // Rinkeby: 10001, BSCtestnet: 10002 (Full list coming soon!)
        uint stargatePoolId,                    // 1 => USDC on testnets
        uint nativeAmountIn,                    // exact amount of native token coming in on source
        address to,                             // the address to send the destination tokens to
        uint amountOutMin,                      // minimum amount of stargatePoolId token to get out of amm router
        uint amountOutMinSg,                    // minimum amount of stargatePoolId token to get out on destination chain
        uint amountOutMinDest,                  // minimum amount of native token to receive on destination
        uint deadline,                          // overall deadline
        address destStargateComposed            // destination contract. it must implement sgReceive()
    )
        external payable
    {

        require(nativeAmountIn > 0, "nativeAmountIn must be greater than 0");
        require(msg.value.sub(nativeAmountIn) > 0, "stargate requires fee to pay crosschain message");

        uint bridgeAmount;
        // using the amm router, swap native into the Stargate pool token, sending the output token to this contract
        {
            // get the token address of the stargatePoolId Pool token (the usdc in this example)
            Pool pool = IStargateRouter(stargateRouter).getPool(stargatePoolId);
            address bridgeToken = pool.token();

            // create path[] for amm swap
            address[] memory path = new address[](2);
            path[0] = IUniswapV2Router02(ammRouter).WETH();    // native IN requires that we specify the WETH in path[0]
            path[1] = bridgeToken;                             // the bridge token,

            uint[] memory amounts = IUniswapV2Router02(ammRouter).swapExactETHForTokens{value:nativeAmountIn}(
                amountOutMin,
                path,
                address(this),
                deadline
            );

            bridgeAmount = amounts[1];
            require(bridgeAmount > 0, 'error: ammRouter gave us 0 tokens to swap() with stargate');

            // this contract needs to approve the stargateRouter to spend its path[1] token!
            IERC20(bridgeToken).approve(address(stargateRouter), bridgeAmount);
        }

        // encode payload data to send to destination contract, which it will handle with sgReceive()
        bytes memory data;
        {
            data = abi.encode(OUT_TO_NATIVE, deadline, amountOutMinDest, to);
        }

        // Stargate's Router.swap() function sends the tokens to the destination chain.
        IStargateRouter(stargateRouter).swap{value:msg.value.sub(nativeAmountIn)}(
            destChainId,
            stargatePoolId,
            msg.sender,                                     // refund adddress. if msg.sender pays too much gas, return extra eth
            bridgeAmount,                                   // total tokens to send to destination chain
            amountOutMinSg,                                 // minimum
            500000,                                         // gasLimit for the receiving contract
            abi.encodePacked(destStargateComposed),         // destination address, the sgReceive() implementer
            data                                            // bytes payload
        );
    }

    // 2. swap native on source for tokens on destination
    function swapNativeForTokens(
        uint16 destChainId,                     // Rinkeby: 10001, BSCtestnet: 10002
        uint stargatePoolId,                    // 1 => USDC on testnets
        uint nativeAmountIn,                    // exact amount of native token coming in on source
        address to,                             // the address to send the destination tokens to
        uint amountOutMin,                      // minimum amount of stargatePoolId token to get out of amm router
        uint amountOutMinSg,                    // minimum amount of stargatePoolId token to get out on destination chain
        uint amountOutMinDest,                  // minimum amount of 'destinationOutToken' to receive on destination
        uint deadline,                          // overall deadline
        address destinationOutToken,            // the token to be received on the destination to the 'to' address
        address destStargateComposed            // address of the destination SushiComposed contract
    ) external payable {

        require(nativeAmountIn > 0, "nativeAmountIn must be greater than 0");
        require(msg.value.sub(nativeAmountIn) > 0, "stargate requires fee to pay crosschain message");

        uint bridgeAmount;

        // perform the ammRouter swap
        {
            // get the token address of the stargatePoolId Pool token (the usdc)
            Pool pool = IStargateRouter(stargateRouter).getPool(stargatePoolId);
            address bridgeToken = pool.token();

            // create path[] for ammRouter swap
            address[] memory path = new address[](2);
            path[0] = IUniswapV2Router02(ammRouter).WETH();     // native IN requires that we specify the WETH in path[0]
            path[1] = bridgeToken;                              // the bridge token. the stargatePoolId asset

            uint[] memory amounts = IUniswapV2Router02(ammRouter).swapExactETHForTokens{value:nativeAmountIn}(
                amountOutMin,
                path,
                address(this),
                deadline
            );
            bridgeAmount = amounts[1];
            require(bridgeAmount > 0, 'error: ammRouter gave us 0 tokens to bridge');

            // address(this) needs to approve the stargateRouter to spend its path[1] token!
            IERC20(bridgeToken).approve(address(stargateRouter), bridgeAmount);
        }

        // encode payload data to send to destination contract, which it will handle with sgReceive()
        bytes memory data;
        {
            data = abi.encode(destinationOutToken, deadline, amountOutMinDest, to);
        }

        // Stargate's Router.swap() function sends the tokens to the destination chain.
        IStargateRouter(stargateRouter).swap{value:msg.value.sub(nativeAmountIn)}(
            destChainId,
            stargatePoolId,
            msg.sender,                                     // refund adddress. if msg.sender pays too much gas, return extra eth
            bridgeAmount,                                   // total tokens to send to destination chain
            amountOutMinSg,                                 // minimum
            500000,                                         // gasLimit for the receiving contract
            abi.encodePacked(destStargateComposed),         // destination address, the sgReceive() implementer
            data                                            // bytes payload
        );

    }

    // 3. swap Tokens on source for Native on destination. 
    //    left to the reader to figure out how to implement
    //function swapTokensForNative(...){}

    // 4. swap Tokens on source for Tokens on destination. 
    function swapTokensForTokens(
        uint16 destChainId,             // Rinkeby: 10001, BSCtestnet: 10002
        uint stargatePoolId,            // 1 => USDC on testnets
        uint srcTokenAmountIn,          // exact amount of src token coming in
        address to,                     // the address to send the destination tokens to
        uint amountOutMin,              // minimum amount of stargatePoolId token to get out of amm router
        uint amountOutMinSg,            // minimum amount of stargatePoolId token to get out on destination chain
        uint amountOutMinDest,          // minimum amount of 'destinationOutToken' to receive on destination
        uint deadline,                  // overall deadline
        address srcInToken,             // the token to be received on src chain
        address destinationOutToken,    // the token to be received on the destination to the 'to' address
        address destStargateComposed    // address of the destination SushiComposed contrac
    ) external payable {
        require(srcTokenAmountIn > 0, "srcTokenAmountIn must be greater than zero");
        require(msg.value > 0, "stargate requires fee to pay for crosschain message");

        uint bridgeAmount;

        // perform the amm router swap
        {
            // get the token address of the stargatePoolId Pool token (the usdc)
            Pool pool = IStargateRouter(stargateRouter).getPool(stargatePoolId);
            address bridgeToken = pool.token();

            if(bridgeToken != srcInToken) {
                // create path for ammRouter swap
                address[] memory path = new address[][2];
                path[0] = srcInToken;
                path[1] = bridgeToken;

                uint[] memory amounts = IUniswapV2Router02(ammRouter).swapExactTokensForTokens(
                    srcTokenAmountIn,
                    amountOutMin,
                    path,
                    address(this),
                    deadline
                );

                bridgeAmount = amounts[1];
            } else {
                // src input token is same as bridge token
                bridgeAmount = srcTokenAmountIn;
            }

            require(bridgeAmount > 0, 'error: ammRouter gave us 0 tokens to swap() with stargate');

            // this contract needs to approve the stargateRouter to spend its bridgeToken
            IERC20(bridgeToken).approve(address(stargateRouter), bridgeAmount);
        }

        // encode payload data to send to destination contract, which it will handle with sgReceive()
        bytes memory data;
        {
            data = abi.encode(destinationOutToken, deadline, amountOutMinDest, to);
        }

        uint l0Fee = IStargateRouter(stargateRouter).quoteLayerZeroFee(
            destChainId,
            1,
            abi.encodePacked(destStargateComposed),
            data
        );

        require(msg.value.sub(l0Fee) > 0, "Insufficient l0 fee");

        // Stargate's Router.swap() function sends the tokens to the destination chain.
        IStargateRouter(stargateRouter).swap{value:l0Fee}(
            destChainId,
            stargatePoolId,
            msg.sender,                                     // refund adddress. if msg.sender pays too much gas, return extra eth
            bridgeAmount,                                   // total tokens to send to destination chain
            amountOutMinSg,                                 // minimum
            500000,                                         // gasLimit for the receiving contract
            abi.encodePacked(destStargateComposed),         // destination address, the sgReceive() implementer
            data                                            // bytes payload
        );
    }

    //-----------------------------------------------------------------------------------------------------------------------
    // STARGATE RECEIVER - the destination contract must implement this function to receive the tokens and payload
    function sgReceive(uint16 _chainId, bytes memory _srcAddress, uint _nonce, address _token, uint amountLD, bytes memory payload) override external {
        require(msg.sender == address(stargateRouter), "only stargate router can call sgReceive!");

        (address _tokenOut, uint _deadline, uint _amountOutMin, address _toAddr) = abi.decode(payload, (address, uint, uint, address));

        // so that router can swap our tokens
        IERC20(_token).approve(address(ammRouter), amountLD);

        uint _toBalancePreTransferOut = address(_toAddr).balance; 

        if(_tokenOut == address(0x0)){
            // they want to get out native tokens
            address[] memory path = new address[](2);
            path[0] = _token;
            path[1] = IUniswapV2Router02(ammRouter).WETH();

            // use ammRouter to swap incoming bridge token into native tokens
            try IUniswapV2Router02(ammRouter).swapExactTokensForETH(
                amountLD,           // the stable received from stargate at the destination
                _amountOutMin,      // slippage param, min amount native token out
                path,               // path[0]: stabletoken address, path[1]: WETH from sushi router
                _toAddr,            // the address to send the *out* native to
                _deadline           // the unix timestamp deadline
            ) {
                // success, the ammRouter should have sent the eth to them
                emit ReceivedOnDestination(OUT_TO_NATIVE, address(_toAddr).balance.sub(_toBalancePreTransferOut));
            } catch {
                // send transfer _token/amountLD to msg.sender because the swap failed for some reason
                IERC20(_token).transfer(_toAddr, amountLD);
                emit ReceivedOnDestination(_token, amountLD);
            }

        } else { // they want to get out erc20 tokens
            uint _toAddrTokenBalancePre = IERC20(_tokenOut).balanceOf(_toAddr);
            address[] memory path = new address[](2);
            path[0] = _token;
            path[1] = _tokenOut;
            try IUniswapV2Router02(ammRouter).swapExactTokensForTokens(
                amountLD,           // the stable received from stargate at the destination
                _amountOutMin,      // slippage param, min amount native token out
                path,               // path[0]: stabletoken address, path[1]: WETH from ammRouter
                _toAddr,            // the address to send the *out* tokens to
                _deadline           // the unix timestamp deadline
            ) {
                // success, the ammRouter should have sent the eth to them
                emit ReceivedOnDestination(_tokenOut, IERC20(_tokenOut).balanceOf(_toAddr).sub(_toAddrTokenBalancePre));
            } catch {
                // transfer _token/amountLD to msg.sender because the swap failed for some reason.
                // this is not the ideal scenario, but the contract needs to deliver them eth or USDC.
                IERC20(_token).transfer(_toAddr, amountLD);
                emit ReceivedOnDestination(_token, amountLD);
            }
        }
    }

}