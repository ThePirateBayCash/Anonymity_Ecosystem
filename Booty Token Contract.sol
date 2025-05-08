// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUniswapPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface TreasureChest{
    function withdraw(address token, address recipient) external;
}

contract Coffer is IERC20, Ownable, ReentrancyGuard {
    string private constant _name = "Doubloon";
    string private constant _symbol = "DOUBLOON";
    uint8 private constant _decimals = 18;

    using Address for address;
    using SafeERC20 for IERC20;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    address[] private _excluded;
    
    mapping (address => mapping (address => uint256)) public treasureChestDeadline;
    mapping (address => address) public treasureChestToken;
    bytes treasureChestCode;

    mapping(address => uint256) private _lastBuyTime;
    bool public checkBot = true;
    uint8 public constant botCooldown  = 30; // 30 seconds AntiBot protection

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 373 * 10**6 * 10**_decimals;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;
    uint8 private _taxFee = 9; // Reflections hardcoded 9%
    uint256 public _maxTxAmount;
    uint8 private _maxTxAmountPercent;
    bool private _takeFee = true;
    address public constant burnAddress = 0x000000000000000000000000000000000000dEaD;

    event Burn(address indexed from, uint256 indexed value);
    event TokensLocked(address indexed beneficiary, address indexed token, address treasureChest, uint256 amount, uint256 indexed releaseTimestamp);
    event TokensUnlocked(address indexed beneficiary, address indexed token, address indexed treasureChest);
    
    modifier isBot(address from, address to) {
        if (checkBot) {
            address buyer = (isLPPair(from)) ? to :
                            (isLPPair(to)) ? from : address(0);
            require(buyer == address(0) || block.timestamp >= _lastBuyTime[buyer] + botCooldown, "Cooldown landlubber!");
            if (buyer != address(0)) {
                _lastBuyTime[buyer] = block.timestamp;
            }
        }
        _;
    }

    constructor() Ownable(msg.sender) {
        _rOwned[msg.sender] = _rTotal;

        _excludeFromFee(owner());
        _excludeFromReward(owner());
        _excludeFromFee(address(this));
        _excludeFromReward(address(this));
        _excludeFromReward(burnAddress);
        _maxTxAmountPercent = 100;

        emit Transfer(address(0), msg.sender, _tTotal);
    }
    
    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) external view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "Ye cannot send more doubloons than allowed!");

        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "Ye cannot be left with less than naught in yer allowance!");

        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function isExcludedFromReward(address account) external view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() external view returns (uint256) {
        return _tFeeTotal;
    }

    function TaxFee() external view returns (uint8) {
        return _taxFee;
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) external view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than the total doubloons aboard!");
        (uint256 rAmount, uint256 rTransferAmount,,,) = _getValues(tAmount);
        if (!deductTransferFee) {
            return rAmount;
        } else {
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than the total plundered reflections!");
        uint256 currentRate =  _getRate();
        return rAmount / currentRate;
    }

    function setCheckBot(bool _status) external onlyOwner {
        checkBot = _status;
    }

    function excludeFromReward(address account) external onlyOwner() {
        _excludeFromReward(account);
    }

    function _excludeFromReward(address account) private {
        require(!_isExcluded[account], "This pirate is already sailing under special conditions!");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "This pirate isn't sailing under special conditions!");
        uint256 length = _excluded.length;
        for (uint256 i = 0; i < length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) external onlyOwner {
        _excludeFromFee(account);
    }

    function _excludeFromFee(address account) private {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee);
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tTransferAmount = tAmount - tFee;
        return (tTransferAmount, tFee);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount * currentRate;
        uint256 rFee = tFee * currentRate;
        uint256 rTransferAmount = rAmount - rFee;
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return tSupply == 0 ? _rTotal / _tTotal : rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        uint256 length = _excluded.length;
        for (uint256 i = 0; i < length; i++) {
            address account = _excluded[i];
            if (_rOwned[account] > rSupply || _tOwned[account] > tSupply) return (_rTotal, _tTotal);
            rSupply -= _rOwned[account];
            tSupply -= _tOwned[account];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount * _taxFee / 100;
    }
    
    function removeAllFee() private {
        if(_taxFee == 0) return;
        _taxFee = 0;
    }

    function restoreAllFee() private {
        _taxFee = 9;
    }

    function MaxTxAmount() public view returns(uint256) {
        return (_tTotal * _maxTxAmountPercent) / 100; 
    }

    function setMaxTxAmountPercent(uint8 percent) external onlyOwner {
        require (percent >= 1 && percent <= 100, "1% minimum possible value");
        _maxTxAmountPercent = percent;
    }

    function isLPPair(address target) public view returns (bool) {
        if (target.code.length == 0) {
            return false;
        }
        try IUniswapPair(target).token1() returns (address) {
            if (IUniswapPair(target).token0() == address(this) || IUniswapPair(target).token1() == address(this)) {
                return true;
            } else {
                return false;
            }
        } catch {
            return false;
        }
    }

    function isExcludedFromFee(address account) external view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "Ye cannot approve from a ship that does not exist!");
        require(spender != address(0), "Ye cannot approve to a ship that does not exist!");
        require(amount != 0, "Ye cannot send naught: approve amount must be above zero!");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private nonReentrant {
        require(from != address(0), "Ye cannot send from a ship that does not exist!");
        require(to != address(0), "Ye cannot transfer doubloons to a ship that does not exist!");
        require(amount != 0, "Ye cannot send naught: transfer amount must be above zero!");
        if(msg.sender != owner() || isLPPair(from) || isLPPair(to)) {
            require(amount <= MaxTxAmount(), "AntiWhale: Yer trade transaction be too large for the seas!");
        }
        
        bool takeFee = true;
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to] || !_takeFee || (!isLPPair(from) && !isLPPair(to))) {
            takeFee = false;
        }

        _tokenTransfer(from,to,amount,takeFee);

        if (isLPPair(to) && !_isExcluded[to]) {
            _excludeFromReward(to);            
        }
    }

    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        if(!takeFee) {
            removeAllFee();
        }
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount,  uint256 tFee) = _getValues(tAmount);
        _rOwned[sender] -= rAmount;
        _rOwned[recipient] += rTransferAmount;    
        _reflectFee(rFee, tFee);
         emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _rOwned[sender] -= rAmount;
        _tOwned[recipient] += tTransferAmount;
        _rOwned[recipient] += rTransferAmount;
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _tOwned[sender] -= tAmount;
        _rOwned[sender] -= rAmount;
        _rOwned[recipient] += rTransferAmount;
       _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _tOwned[sender] -= tAmount;
        _rOwned[sender] -= rAmount;
        _tOwned[recipient] += tTransferAmount;
        _rOwned[recipient] += rTransferAmount;
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function burn (uint256 amount) external {
        _transfer(msg.sender, burnAddress, amount);
        emit Burn(msg.sender, amount);
    }

    function TakeFee (bool take) external onlyOwner {
        _takeFee = take;
    }

    function updateTreasureChest (bytes calldata _treasureChestCode) external onlyOwner {
        treasureChestCode = _treasureChestCode;
    }

    function lockTokens(address token, uint256 amount, uint256 lockTime) external nonReentrant returns(address){
        require(lockTime >= 60, "Too quick, matey! The minimum lock time is 60 seconds. Set sail for a proper duration and try again!");
        require(IERC20(token).allowance(msg.sender,address(this)) >= amount, "Hold up, pirate! The lock amount exceeds yer allowance. Adjust yer treasure or grant more allowance to proceed.");
        require(amount > 0, "Avast! Ye can not lock an empty chest! The lock amount must be greater than zero. Adjust yer stash and try again!");
        bool _senderExcluded = false;
        if (_isExcludedFromFee[msg.sender]) {
            _senderExcluded = true;
        } else {
            _isExcludedFromFee[msg.sender] = true;
        }
        bytes memory _treasureChestCode = treasureChestCode;
        uint256 salt = uint256(keccak256(abi.encodePacked(lockTime, address(this), msg.sender, token, amount, block.prevrandao, gasleft())));
        address treasureChestAddr;
        assembly {
          treasureChestAddr := create2(0, add(_treasureChestCode, 0x20), mload(_treasureChestCode), salt)
          if iszero(extcodesize(treasureChestAddr)) {
            revert(0, 0)
          }
        }
        IERC20(token).safeTransferFrom(msg.sender, treasureChestAddr, amount);
        treasureChestDeadline[msg.sender][treasureChestAddr] = block.timestamp + lockTime;
        treasureChestToken[treasureChestAddr] = token;
        _isExcludedFromFee[treasureChestAddr] = true;
        if (_isExcluded[msg.sender]) {
            _excludeFromReward(treasureChestAddr);
        }
        if (!_senderExcluded) {
            _isExcludedFromFee[msg.sender] = false;
        }
        emit TokensLocked(msg.sender, token, treasureChestAddr, amount, treasureChestDeadline[msg.sender][treasureChestAddr]);
        return treasureChestAddr;
    }

    function unlockTokens(address _treasureChestAddr) external nonReentrant {
        require(treasureChestDeadline[msg.sender][_treasureChestAddr] != 0, "No treasure chest be linked to yer address! ");
        require(treasureChestDeadline[msg.sender][_treasureChestAddr] <= block.timestamp, "The treasure chest is still locked, and it is too early to claim yer booty. Patience, pirate!");
        bool _senderExcluded = false;
        if (_isExcludedFromFee[msg.sender]) {
            _senderExcluded = true;
        } else {
            _isExcludedFromFee[msg.sender] = true;
        }
        TreasureChest(_treasureChestAddr).withdraw(treasureChestToken[_treasureChestAddr],msg.sender);
        if (!_senderExcluded) {
            _isExcludedFromFee[msg.sender] = false;
        }
        emit TokensUnlocked(msg.sender, treasureChestToken[_treasureChestAddr],  _treasureChestAddr);
        delete treasureChestDeadline[msg.sender][_treasureChestAddr];
        delete treasureChestToken[_treasureChestAddr];
    }
}
