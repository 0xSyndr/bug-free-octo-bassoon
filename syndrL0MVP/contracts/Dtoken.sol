// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./libs/Address.sol";
import "./libs/BytesLib.sol";
import "./libs/access/Ownable.sol";
import "./libs/utils/Context.sol";
import "./interfaces/IDToken.sol";
import "./interfaces/LayerZero/ILayerZeroEndpoint.sol";

contract DToken is Context, Ownable, IDToken {
    using Address for address;
    using BytesLib for bytes;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    // User data for DToken
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // token whitelist for diff chains
    mapping(uint16 => bytes) private _srcTokenWhiteList;
    mapping(uint16 => bool) private _isChainSupported;

    uint16[] public supportedChains;

    // --- Addresses ---
    // This remains same on all chains as
    // syndrSyntheticIssuerAddress exists on AVAX C-chain only
    address public immutable syndrSyntheticIssuerAddress;

    ILayerZeroEndpoint public endpoint;

    /**
     * @dev Sets the values for {name}, {symbol}, {layerZeroEndpoint} & {syndrSyntheticIssuerAddress}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All 3 addresses are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_, address _layerZeroEndpoint, address _syndrSyntheticIssuerAddress) {
        require(_syndrSyntheticIssuerAddress.isContract(), "DToken: syndrSyntheticIssuerAddress address is not a contract");
        require(_layerZeroEndpoint.isContract(), "DToken: layerZeroEndpoint address is not a contract");

        _name = name_;
        _symbol = symbol_;

        syndrSyntheticIssuerAddress = _syndrSyntheticIssuerAddress;
        endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        // emit SyndrSyntheticIssuerAddressChanged(_syndrSyntheticIssuerAddress);
    }

    // --- Functions for intra-Syndr calls ---

    /**
     * @dev Mints `amount` of dTokens for `_account`.
     *
     * Requirements:
     *
     * - `_account` cannot be the zero address.
     * - the caller must be `syndrSyntheticIssuerAddress`.
     */
    function mint(address _account, uint256 _amount) external override {
        _requireCallerIsSyndrSyntheticIssuer();
        require(block.chainid == 43114,"mint only allowed on avax c-chain");
        _mint(_account, _amount);
    }

    /**
     * @dev Burn `_amount` of dTokens for `_account`.
     *
     * Requirements:
     *
     * - `_account` cannot be the zero address.
     * - the caller must be one of `syndrSyntheticIssuerAddress`, `stabilityPoolAddress` or `vaultManagerAddress`.
     */
    function burn(address _account, uint256 _amount) external override {
        _requireCallerIsSyndrSIorVaultMorSP();
        require(block.chainid == 43114,"burn only allowed on avax c-chain");
        _burn(_account, _amount);
    }

    // send tokens to another chain.
    // this function sends the tokens from your address to the same address on the destination.
    function sendTokens(
        uint16 _chainId,                            // send tokens to this chainId
        bytes calldata _dstMultiChainTokenAddr,     // destination address of MultiChainToken
        uint _qty                                   // how many tokens to send
    )
        public
        payable
        override
    {
        // TO-DO: explore cross attack vectors to avoid getting rekt!!!!!
        _requireVaildCrossChainRecipient(msg.sender);
        // _requireVaildCrossChainRecipient(msg.sender, _chainId);

        // burn the tokens locally.
        // tokens will be minted on the destination.
        require(
            allowance(msg.sender, address(this)) >= _qty,
            "You need to approve the contract to send your tokens!"
        );

        // and burn the local tokens *poof*
        _burn(msg.sender, _qty); 

        // abi.encode() the payload with the values to send
        bytes memory payload = abi.encode(msg.sender, _qty);

        // send LayerZero message
        endpoint.send{value:msg.value}(
            _chainId,                       // destination chainId
            _dstMultiChainTokenAddr,        // destination address of MultiChainToken
            payload,                        // abi.encode()'ed bytes
            payable(msg.sender),            // refund address (LayerZero will refund any superflous gas back to caller of send()
            address(0x0),                   // 'zroPaymentAddress' unused for this mock/example
            bytes("")                       // 'txParameters' unused for this mock/example
        );
    }

    // --- LayerZero function ---

    // --- adding chain support ----
    function whitelistChain(uint16 _chainId, bytes calldata _srcToken) external onlyOwner {
        require(_isChainSupported[_chainId] == false, "Chain already supported!");
        _isChainSupported[_chainId] = true;
        _srcTokenWhiteList[_chainId] = _srcToken;
        supportedChains.push(_chainId);
    }

    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 , bytes calldata _payload) external override {
        require(msg.sender == address(endpoint)); // boilerplate! lzReceive must be called by the endpoint for security
        require(_isChainSupported[_srcChainId] == true, "Chain not supported");
        require(_srcAddress.equal(_srcTokenWhiteList[_srcChainId]), "_srcAddress is not whitelisted");

        // decode
        (address toAddr, uint qty) = abi.decode(_payload, (address, uint));

        // mint the tokens back into existence, to the toAddr from the message payload
        _mint(toAddr, qty);
    }

    // --- External functions ---

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _requireValidRecipient(recipient);
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _requireValidRecipient(recipient);
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    // --- Internal operations ---

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    // --- 'require' functions ---
    function _requireVaildCrossChainRecipient(address _recipient) internal view {
        require(_recipient != address(0), "DToken: Cannot transfer tokens directly to zero address");
        require(
            _recipient != syndrSyntheticIssuerAddress, 
            "DToken: Cannot transfer tokens directly to the SyndrSyntheticIssuer addr on any chain"
        );
        // attack vectors::""??
    }

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && 
            _recipient != address(this),
            "DToken: Cannot transfer tokens directly to the DToken token contract or the zero address"
        );
        require(
            _recipient != syndrSyntheticIssuerAddress, 
            "DToken: Cannot transfer tokens directly to the SyndrSyntheticIssuer"
        );
    }

    function _requireCallerIsSyndrSyntheticIssuer() internal view {
        require(_msgSender() == syndrSyntheticIssuerAddress, "DToken: Caller is not SyndrSyntheticIssuer");
    }

    function _requireCallerIsSyndrSIorVaultMorSP() internal view {
        require(
            _msgSender() == syndrSyntheticIssuerAddress,
            "DToken: Caller is neither SyndrSyntheticIssuer nor VaultManager nor StabilityPool"
        );
    }
}