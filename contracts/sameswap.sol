// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

contract OfficialSameChainSwapWithPara is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public routerAddress;
    address public wethToken;
    address public feeReceiver;
    uint256 public platformFee;
    uint256 public constant feeBps = 1000;
    uint256 public constant MAX_PLATFORM_FEE = 2000;

    event FeeReceiverSet(address indexed _oldReceiver, address indexed _newReceiver);

    constructor(uint256 _fee, address _routerAddress, address _wethToken, address _feeReceiver) Ownable(msg.sender) {
        platformFee = _fee;
        routerAddress = _routerAddress;
        wethToken = _wethToken;
        feeReceiver = _feeReceiver;
    }

    function executeSwap(
        bool isETHIn,
        bool isETHOut,
        address _tokenA,
        address _tokenB,
        uint256 _amountIn,
        bool isSource,
        bytes calldata data,
        bytes calldata data2
    ) public payable nonReentrant {
        if (isETHIn) {
            IWETH(wethToken).deposit{value: msg.value}();
            checkAndApproveAll(wethToken, routerAddress, msg.value);
        } else {
            IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), _amountIn);
            checkAndApproveAll(_tokenA, routerAddress, _amountIn);
        }

        uint256 beforeBalance = IERC20(_tokenB).balanceOf(address(this));
        (bool success, ) = routerAddress.call(data);
        require(success, 'Call to paraswap router failed');

        uint256 afterBalance = IERC20(_tokenB).balanceOf(address(this));
        uint256 amountOut = afterBalance - beforeBalance;
        uint256 feeAmountOut = (amountOut * platformFee) / (feeBps * 100);

        if (isETHOut) {
            if (isSource) {
                IWETH(wethToken).withdraw(amountOut);
                payable(msg.sender).transfer(amountOut);
            } else {
                IWETH(wethToken).withdraw(amountOut - feeAmountOut);
                payable(msg.sender).transfer(amountOut - feeAmountOut);
            }
        } else {
            if (isSource) {
                IERC20(_tokenB).safeTransfer(msg.sender, amountOut);
            } else {
                IERC20(_tokenB).safeTransfer(msg.sender, amountOut - feeAmountOut);
            }
        }

        if (isSource) {
            uint256 feeAmountIn = (_amountIn * platformFee) / (feeBps * 100);
            if (_tokenA == wethToken) {
                IWETH(wethToken).withdraw(feeAmountIn);
                payable(feeReceiver).transfer(feeAmountIn);
            } else {
                uint256 beforeWETHBalance = IERC20(wethToken).balanceOf(address(this));
                (bool success2, ) = routerAddress.call(data2);
                require(success2, 'Call to paraswap router failed');
                uint256 afterWETHBalance = IERC20(wethToken).balanceOf(address(this));
                uint256 amountWETHOut = afterWETHBalance - beforeWETHBalance;
                IWETH(wethToken).withdraw(amountWETHOut);
                payable(feeReceiver).transfer(amountWETHOut);
            }
        } else {
            IWETH(wethToken).withdraw(feeAmountOut);
            payable(feeReceiver).transfer(feeAmountOut);
        }
    }
    function changeFeeData(uint256 _fee, address _feeReceiver) external onlyOwner {
        require(_fee <= MAX_PLATFORM_FEE, 'Platform fee exceeds the maximum limit');
        platformFee = _fee;
        address oldReceiver = feeReceiver;
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(oldReceiver, _feeReceiver);
    }

    function checkAndApproveAll(address _token, address _target, uint256 _amountToCheck) internal {
        if (IERC20(_token).allowance(address(this), _target) < _amountToCheck) {
            IERC20(_token).forceApprove(_target, 0);
            IERC20(_token).forceApprove(_target, ~uint256(0));
        }
    }

    // fallback function to receive ETH
    receive() external payable {}
}