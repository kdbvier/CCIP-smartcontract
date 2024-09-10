// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libs/BytesLib.sol";

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) external pure returns (uint amountB);
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut);
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface IV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }
    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
    }
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable returns (uint256 amountIn);

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountOut);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountIn);

    function WETH9() external view returns (address);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

contract ParaSameSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    address public immutable paraRouter;
    IUniswapV2Router02 public immutable v2Router;
    IV3SwapRouter public immutable v3Router;
    address public wethToken;
    address public feeReceiver;
    uint256 public platformFee; // Fee must be by 1000, so if you want 5% this will be 5000
    uint256 public constant feeBps = 1000; // 1000 is 1% so we can have many decimals
    uint256 public constant MAX_PLATFORM_FEE = 2000;

    error FailedCall();
    ////================= Events ===================////
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint amountIn,
        uint amountOut
    );
    event FeeReceiverSet(
        address indexed _oldReceiver,
        address indexed _newReceiver
    );
    event FeeSent(address feeReceiver, uint256 amount);

    constructor(
        address _paraRouter,
        address _v2Router,
        address _v3Router,
        address _wethToken,
        uint256 _fee,
        address _feeReceiver
    ) Ownable(msg.sender) {
        paraRouter = _paraRouter;
        v2Router = IUniswapV2Router02(_v2Router);
        v3Router = IV3SwapRouter(_v3Router);
        wethToken = _wethToken;
        platformFee = _fee;
        feeReceiver = _feeReceiver;
    }

    function changeFeeData(
        uint256 _fee,
        address _feeReceiver
    ) external onlyOwner {
        require(
            _fee <= MAX_PLATFORM_FEE,
            "Platform fee exceeds the maximum limit"
        );
        platformFee = _fee;
        address oldReceiver = feeReceiver;
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(oldReceiver, _feeReceiver);
    }

    function paraSwap(
        address _tokenA,
        address _tokenB,
        bool _isETHIn,
        bool _isETHOut,
        bool _usePara,
        uint256 _amountIn,
        uint256 _minAmountOutV2,
        uint256 _minAmountOutV3,
        uint8 _buyOneTwoOrThree, // 1 means buy only v2, 2 means buy v3 only, 3 means buy first v2 then v3, 4 means buy first v3 then v2
        address[] memory _pathV2,
        bytes memory _pathV3,
        bytes calldata _data,
        bytes calldata _feeData
    ) public payable nonReentrant {
        if (_isETHIn) {
            require(msg.value > 0, "invalid eth amount");
            _amountIn = msg.value;
            IWETH(wethToken).deposit{value: msg.value}();
        } else {
            uint256 beforeTransfer = IERC20(_tokenA).balanceOf(address(this));
            IERC20(_tokenA).safeTransferFrom(
                msg.sender,
                address(this),
                _amountIn
            );
            uint256 afterTransfer = IERC20(_tokenA).balanceOf(address(this));
            _amountIn = afterTransfer - beforeTransfer;
        }
        uint256 output;
        bool useOld = false;
        uint256 feeAmount;
        if (_usePara) {
            feeAmount = (_amountIn * platformFee) / (feeBps * 100);
            uint256 amountIn = _amountIn - feeAmount;
            checkAndApproveAll(_tokenA, paraRouter, _amountIn);
            uint256 beforeBalance = IERC20(_tokenB).balanceOf(address(this));
            (bool success, ) = paraRouter.call(_data);
            if (success) {
                (bool feeSuccess, ) = paraRouter.call(_feeData);
                uint256 afterBalance = IERC20(_tokenB).balanceOf(address(this));
                output = afterBalance - beforeBalance;
            } else {
                useOld = true;
            }
        } else {
            useOld = true;
        }

        if (useOld) {
            if (_buyOneTwoOrThree == 1) {
                feeAmount = (_amountIn * platformFee) / (feeBps * 100);
                if (_pathV2[0] != wethToken) {
                    // WETH => Token
                    address[] memory path = new address[](2);
                    path[0] = _pathV2[0];
                    path[1] = wethToken;
                    v2Swap(path, feeAmount, 0);
                }
                output = v2Swap(
                    _pathV2,
                    _amountIn - feeAmount,
                    _minAmountOutV2
                );
            } 
            else if (_buyOneTwoOrThree == 2) {
                feeAmount = (_amountIn * platformFee) / (feeBps * 100);
                if (_pathV3.toAddress(0) == wethToken) {
                    // WETH => output Token
                    output = v3Swap(
                        _tokenA,
                        _pathV3,
                        _amountIn - feeAmount,
                        _minAmountOutV3
                    );
                } else if (
                    _pathV3.toAddress(23) == wethToken && _tokenB == wethToken
                ) {
                    // Token => WETH
                    output = v3Swap(
                        _tokenA,
                        _pathV3,
                        _amountIn,
                        _minAmountOutV3
                    );
                    feeAmount = (output * platformFee) / (feeBps * 100);
                    output = output - feeAmount;
                } else {
                    // Token => WETH (stable coins) => Token
                    v3Swap(_tokenA, _pathV3.slice(0, 43), feeAmount, 0);
                    output = v3Swap(
                        _tokenA,
                        _pathV3,
                        _amountIn - feeAmount,
                        _minAmountOutV3
                    );
                }
            } 
            else if (_buyOneTwoOrThree == 3) {
                output = v2Swap(_pathV2, _amountIn, _minAmountOutV2);
                feeAmount = (output * platformFee) / (feeBps * 100);
                output = v3Swap(
                    _pathV2[_pathV2.length - 1],
                    _pathV3,
                    output - feeAmount,
                    _minAmountOutV3
                );
            } else if (_buyOneTwoOrThree == 4) {
                output = v3Swap(_tokenA, _pathV3, _amountIn, _minAmountOutV3);
                feeAmount = (output * platformFee) / (feeBps * 100);
                output = v2Swap(_pathV2, output - feeAmount, _minAmountOutV2);
            }
        }

        if (_isETHOut && _tokenB == wethToken) {
            IWETH(wethToken).withdraw(output);
            (bool success, ) = msg.sender.call{value: output}("");
            if (!success) {
                revert FailedCall();
            }
        } else {
            IERC20(_tokenB).safeTransfer(msg.sender, output);
        }
        if (IWETH(wethToken).balanceOf(address(this)) > 0) {
            IWETH(wethToken).withdraw(
                IWETH(wethToken).balanceOf(address(this))
            );
            payable(feeReceiver).transfer(address(this).balance);
            emit FeeSent(feeReceiver, address(this).balance);
        }
        emit SwapExecuted(_tokenA, _tokenB, _amountIn, output);
    }

    function checkAndApproveAll(
        address _token,
        address _target,
        uint256 _amountToCheck
    ) internal {
        if (IERC20(_token).allowance(address(this), _target) < _amountToCheck) {
            IERC20(_token).forceApprove(_target, 0);
            IERC20(_token).forceApprove(_target, _amountToCheck);
        }
    }

    function v2Swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minAmountOut // Slippage in base of 1000 meaning 10 is 1% and 1 is 0.1% where 1000 is 1
    ) internal returns (uint256) {
        address tokenOut = _path[_path.length - 1];
        checkAndApproveAll(_path[0], address(v2Router), _amountIn);
        uint256 initial = IERC20(tokenOut).balanceOf(address(this));
        v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            _minAmountOut,
            _path,
            address(this),
            block.timestamp + 1 hours
        );
        uint256 finalAmount = IERC20(tokenOut).balanceOf(address(this));
        return finalAmount - initial;
    }

    function v3Swap(
        address _tokenIn,
        bytes memory _path,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 amountOutput) {
        checkAndApproveAll(_tokenIn, address(v3Router), _amountIn);
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams(_path, address(this), _amountIn, _minAmountOut);
        amountOutput = v3Router.exactInput(params);
    }

    function recoverStuckETH(address payable _beneficiary) public onlyOwner {
        // _beneficiary.transfer(address(this).balance);
        (bool success, ) = _beneficiary.call{value: address(this).balance}("");
        if (!success) {
            revert FailedCall();
        }
    }

    function recoverStuckTokens(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(owner(), amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
