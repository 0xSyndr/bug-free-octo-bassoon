// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./libs/Address.sol";
import "./libs/access/Ownable.sol";
import "./interfaces/ILayerZeroReceiver.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

/**
 * @dev cross chain NFTs
 * Author: Vyom Sharma (Twitter: @ VCrizpy)
 */
contract LayerZeroPunksMarket is Ownable, ILayerZeroReceiver {
    using Address for address;

    enum CrossChainOps {
        setInitialOwner,
        getPunk,
        transferOwnership
    }

    // required: the LayerZero endpoint which is passed in the constructor
    ILayerZeroEndpoint public endpoint;

    string public standard = 'LayerZeroPunks';
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    bool public allPunksAssigned = false;
    uint256 punksRemainingToAssign = 0;

    uint16[] public supportedChainIds;
    mapping(uint16 => bool) public isSupportedChainId;
    mapping(uint16 => address) public chainIdToDstAddress;
    bool public allDstAddressesSet = false;

    //mapping (address => uint) public addressToPunkIndex;
    mapping (uint256 => address) public punkIndexToAddress;

    /* This creates an array with all balances */
    mapping (address => uint256) public balanceOf;

    /* Chain location for a given punk Index */
    mapping (uint256 => uint16) punkIndexToChainId;

    constructor(address _l0endpoint, uint16[] memory _supportedChainIds) {
        endpoint = ILayerZeroEndpoint(_l0endpoint);

        totalSupply = 10;
        punksRemainingToAssign = totalSupply;
        name = "LayerZeroPunks";
        symbol = "L0PNKS";
        decimals = 0;

        for (uint i = 0; i < _supportedChainIds.length; i++) {
            supportedChainIds.push(_supportedChainIds[i]);
            isSupportedChainId[_supportedChainIds[i]] = true;
        }
    }

    function setDstAddresses(uint16[] memory _supportedChainIds, address[] memory _dstAddresses) public onlyOwner {
        require(_supportedChainIds.length == supportedChainIds.length, "LayerZeroPunksMarket: Invalid ChainIds");
        require(_supportedChainIds.length == _dstAddresses.length, "LayerZeroPunksMarket: Invalid dstAddresses");

        for(uint i = 0; i < _supportedChainIds.length; i++) {
            require(isSupportedChainId[_supportedChainIds[i]] == true, "LayerZeroPunksMarket: Only valid chain Ids");
            require(_dstAddresses[i].isContract() == true, "LayerZeroPunksMarket: dtsAddress must be a contract");
            chainIdToDstAddress[_supportedChainIds[i]] = _dstAddresses[i];
        }

        allDstAddressesSet = true;
    }

    function setInitialOwner(address _to, uint256 _punkIdx, uint16 _chainId) public payable onlyOwner allDstAddressesAreSet isValidChainId(_chainId) {
        require(allPunksAssigned == true, "LayerZeroPunksMarket: All punks already assigned");
        require(_punkIdx <= totalSupply, "LayerZeroPunksMarket: Invalid Punk Idx");

        uint256 id;
        assembly {
            id := chainid()
        }
        // require(id == _chainId, "")

        for(uint i = 0; i < supportedChainIds.length; i++) {
            if(id == supportedChainIds[i]) {
                // set L0PNK data on current chain
                if (punkIndexToAddress[_punkIdx] != address(0)) {
                    balanceOf[punkIndexToAddress[_punkIdx]]--;
                } else {
                    punksRemainingToAssign--;
                }
                punkIndexToAddress[_punkIdx] = _to;
                balanceOf[_to]++;
                punkIndexToChainId[_punkIdx] = _chainId;
            } else {
                // sync L0PNK data on other supported chains
                _syncL0PNKData(supportedChainIds[i], CrossChainOps.setInitialOwner, _punkIdx, _to, _chainId);
            }
        }
    }

    function setInitialOwners(address[] memory _addresses, uint256[] memory _indices, uint16[] memory _chainIds) public onlyOwner payable {
        require(_addresses.length == _indices.length, "LayerZeroPunksMarket: invalid indices");
        require(_addresses.length == _chainIds.length, "LayerZeroPunksMarket: invalid chainIds");

        for (uint i = 0; i < _addresses.length; i++) {
            setInitialOwner(_addresses[i], _indices[i], _chainIds[i]);
        }
    }

    function allInitialOwnersAssigned() public onlyOwner {
        allPunksAssigned = true;
        renounceOwnership();
    }

    function getPunk(uint256 _punkIndex) public allPunksAreAssigned  {
        require(punksRemainingToAssign != 0, "LayerZeroPunksMarket: all punks have been taken");
        require(punkIndexToAddress[_punkIndex] == address(0), "LayerZeroPunksMarket: This Punk is taken!");
        require(_punkIndex <= totalSupply, "LayerZeroPunksMarket: Invalid Punk Idx");

        // to-do getPunk
        // punkIndexToAddress[_punkIndex] = msg.sender;
        // balanceOf[msg.sender]++;
        // punksRemainingToAssign--;
        // Assign(msg.sender, _punkIndex);
    }



    // overrides lzReceive function in ILayerZeroReceiver.
    // automatically invoked on the receiving chain after the source chain calls endpoint.send(...)
    function lzReceive(uint16 , bytes memory _fromAddress, uint64 _nonce, bytes memory _payload) override external {
        require(msg.sender == address(endpoint));
        address fromAddress;
        assembly {
            fromAddress := mload(add(_fromAddress, 20))
        }
        // ?? is fromAddress the userApp address or the LZ endpoint address??

        (CrossChainOps _op, uint256 _punkIdx, address _punkOwner, uint16 _punkChainId) = abi.decode(_payload, (CrossChainOps, uint256, address, uint16));
        
        if(_op == CrossChainOps.setInitialOwner) {
            // set L0PNK data on current chain
            if (punkIndexToAddress[_punkIdx] != address(0)) {
                balanceOf[punkIndexToAddress[_punkIdx]]--;
            } else {
                punksRemainingToAssign--;
            }
            punkIndexToAddress[_punkIdx] = _punkOwner;
            balanceOf[_punkOwner]++;
            punkIndexToChainId[_punkIdx] = _punkChainId;
        }
    }

    // custom function that wraps endpoint.send(...) which will 
    // cause lzReceive() to be called on the destination chain!
    // function incrementCounter(uint16 _dstChainId, bytes calldata _dstCounterMockAddress) public payable {
    //     endpoint.send{value:msg.value}(_dstChainId, _dstCounterMockAddress, bytes(""), msg.sender, address(0x0), bytes(""));
    // }

    // custom function that wraps endpoint.send(...) which will 
    // cause lzReceive() to be called on the destination chain!
    function _syncL0PNKData(uint16 _dstChainId, CrossChainOps _op, uint256 _punkIdx, address _punkOwner, uint16 _punkChainId) internal {
        bytes memory punkPayload = abi.encode(_op, _punkIdx, _punkOwner, _punkChainId);
        endpoint.send{value: msg.value}(_dstChainId, addrToPackedBytes(chainIdToDstAddress[_dstChainId]), punkPayload, payable(msg.sender), address(0x0), bytes(""));
    }

    // helpers

    // send() helper function
    function packedBytesToAddr(bytes calldata _b) public pure returns (address){
        address addr;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, sub(_b.offset, 2 ), add(_b.length, 2))
            addr := mload(sub(ptr,10))
        }
        return addr;
    }

    // send() helper function
    function addrToPackedBytes(address _a) public pure returns (bytes memory){
        bytes memory data = abi.encodePacked(_a);
        return data;
    }

    // modifiers 

    modifier isValidChainId(uint16 _chainId) {
        require(isSupportedChainId[_chainId] == true, "Only valid chain Ids");
        _;
    }

    modifier allDstAddressesAreSet() {
        require(allDstAddressesSet == true, "LayerZeroPunksMarket: All dstAddresses are not set");
        _;
    }

    modifier allPunksAreAssigned() {
        require(allPunksAssigned == true, "LayerZeroPunksMarket: All punks are not assigned");
        _;
    }
}