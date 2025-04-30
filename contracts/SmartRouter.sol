// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

library Structs {
    // Add this struct to the Structs library
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactInputParamsWithDeadline {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IDexFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface ISwapRouter {
    function exactInput(Structs.ExactInputParams calldata params) external payable returns (uint256 amountOut);

    function exactInput(
        Structs.ExactInputParamsWithDeadline calldata params
    ) external payable returns (uint256 amountOut);
}

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)
library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, 'divide by zero'); // Solidity automatically throws when dividing by 0
        return a / b;
    }
}

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

contract CSWAPSmartRouter is Ownable, ReentrancyGuard {
    using SafeMath for uint;

    address public immutable WETH;
    address public immutable USDC;
    address public immutable USDT;
    address public feeReceiver;
    uint256 public feePercent;
    uint24 public constant FEE_DIVISOR = 10000;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'CSRouter: EXPIRED');
        _;
    }

    event SwapIn(address indexed wallet, address token, uint256 amountIn, uint256 amountOut);
    event SwapOut(address indexed wallet, address token, uint256 amountIn, uint256 amountOut);

    constructor(address _WETH, address _USDC, address _USDT, address _feeReceiver) Ownable(msg.sender) {
        WETH = _WETH;
        USDC = _USDC;
        USDT = _USDT;
        feeReceiver = _feeReceiver;
        feePercent = 30; // 0.3%
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function updateFeePercent(uint256 newFeePercent) external onlyOwner {
        require(msg.sender == feeReceiver, 'Must use fee receiver to set');
        require(newFeePercent <= 1000, '10% max fee');
        feePercent = newFeePercent;
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
    }

    function recoverStuckTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    function recoverStuckETH(uint256 amount) external onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CSRouter: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CSRouter: ZERO_ADDRESS');
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'CSRouter: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CSRouter: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to, address factory) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(IDexFactory(factory).getPair(input, output));
            uint amountInput;
            uint amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint reserve0, uint reserve1, ) = pair.getReserves();
                (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? IDexFactory(factory).getPair(output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    struct CallStruct {
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        uint256 deadline;
        bool swapWithDeadline;
        address factoryOrSwapRouter;
        bytes encodedPath;
        address to;
    }

    function multicallSwap(CallStruct[] memory _calls) external payable {
        uint256 amountOutPreviousSwap = 0;
        for (uint256 i = 0; i < _calls.length; i++) {
            CallStruct memory myCall = _calls[i];
            uint256 amountIn = myCall.amountIn;
            if (i > 0) {
                amountIn = amountOutPreviousSwap;
            }
            address tokenOut = myCall.path[myCall.path.length - 1]; // Token out
            uint256 balanceInitial;
            if (tokenOut == address(0)) {
                balanceInitial = address(this).balance;
            } else {
                balanceInitial = IERC20(tokenOut).balanceOf(address(this));
            }
            bool isLastItem = i == _calls.length - 1;
            bool fundsAlreadyInside = (_calls.length > 1 && i != 0);
            if (fundsAlreadyInside) {
                require(
                    _calls[i - 1].path[_calls[i - 1].path.length - 1] == _calls[i].path[0],
                    'CSRouter: Middle Token must be same'
                );
            }

            if (myCall.encodedPath.length == 0) {
                swapV2(
                    amountIn,
                    myCall.amountOutMin,
                    myCall.path,
                    myCall.deadline,
                    myCall.factoryOrSwapRouter,
                    myCall.to,
                    fundsAlreadyInside,
                    isLastItem // If it's the last one make it true to take the fee
                );
            } else {
                swapV3(
                    amountIn,
                    myCall.amountOutMin,
                    myCall.path,
                    myCall.deadline,
                    myCall.swapWithDeadline,
                    myCall.factoryOrSwapRouter,
                    myCall.encodedPath,
                    myCall.to,
                    fundsAlreadyInside,
                    isLastItem // If it's the last one make it true to take the fee
                );
            }
            uint256 balanceFinal;
            if (tokenOut == address(0)) {
                balanceFinal = address(this).balance;
            } else {
                balanceFinal = IERC20(tokenOut).balanceOf(address(this));
            }

            amountOutPreviousSwap = balanceFinal - balanceInitial;
        }
    }

    function swapV2(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        uint256 _deadline,
        address _factory,
        address _to,
        bool _fundsAlreadyInside,
        bool _sendPlatformFee
    ) internal ensure(_deadline) {
        address[] memory path = _path;
        if (!_fundsAlreadyInside) {
            if (msg.value > 0) {
                require(path[0] == address(0), 'Path[0] must be address zero for native tokenIn');
                IWETH(WETH).deposit{value: _amountIn}();
                path[0] = WETH;
            } else {
                require(msg.value == 0, 'ETH should not be sent');
                TransferHelper.safeTransferFrom(path[0], msg.sender, address(this), _amountIn);
            }
        }
        bool isNativeOut = false;
        if (path[1] == address(0)) {
            path[1] = WETH;
            isNativeOut = true;
        }
        address pairContract = IDexFactory(_factory).getPair(path[0], path[1]);
        uint256 balanceFinalTokenBefore = IERC20(path[1]).balanceOf(address(this));

        // handle fee
        uint256 amountInAfterFee = handleFee(path[0], path[1], _amountIn, _sendPlatformFee);
        TransferHelper.safeTransfer(path[0], pairContract, amountInAfterFee);
        _swapSupportingFeeOnTransferTokens(path, address(this), _factory);
        uint256 amountOut = IERC20(path[1]).balanceOf(address(this)) - balanceFinalTokenBefore;
        require(amountOut >= _amountOutMin, 'CSRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // handle fee
        uint256 amountOutAfterFee = handleFee(path[1], path[0], amountOut, _sendPlatformFee);
        // Transfer token to sender
        if (_to != address(this)) {
            if (isNativeOut) {
                IWETH(WETH).withdraw(amountOutAfterFee);
                TransferHelper.safeTransferETH(_to, amountOutAfterFee);
            } else {
                TransferHelper.safeTransfer(path[1], _to, amountOutAfterFee);
            }
        }
        emit SwapOut(msg.sender, path[0], amountInAfterFee, amountOutAfterFee);
    }

    function swapV3(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        uint256 _deadline,
        bool _useDeadline,
        address _swapRouter,
        bytes memory _encodedPath,
        address _to,
        bool _fundsAlreadyInside,
        bool _sendPlatformFee
    ) internal ensure(_deadline) {
        require(_path.length >= 2, 'Invalid path length');
        address[] memory path = _path;
        bool isInputETH = path[0] == address(0);
        bool isOutputETH = path[1] == address(0);
        address inputToken = isInputETH ? WETH : path[0];
        address outputToken = isOutputETH ? WETH : path[1];
        if (!_fundsAlreadyInside) {
            if (isInputETH) {
                require(msg.value == _amountIn, 'Incorrect ETH amount sent');
                IWETH(WETH).deposit{value: _amountIn}();
                // WETH is now in this contract
            } else {
                require(msg.value == 0, 'ETH should not be sent');
                TransferHelper.safeTransferFrom(inputToken, msg.sender, address(this), _amountIn);
            }
        }
        // handle fee
        uint256 amountInAfterFee = handleFee(inputToken, outputToken, _amountIn, _sendPlatformFee);
        IERC20(inputToken).approve(_swapRouter, amountInAfterFee);
        uint256 amountOut;
        if (_useDeadline) {
            Structs.ExactInputParamsWithDeadline memory inputParams = Structs.ExactInputParamsWithDeadline({
                path: _encodedPath,
                recipient: address(this),
                deadline: _deadline,
                amountIn: amountInAfterFee,
                amountOutMinimum: _amountOutMin
            });
            amountOut = ISwapRouter(_swapRouter).exactInput{value: 0}(inputParams);
        } else {
            Structs.ExactInputParams memory inputParams = Structs.ExactInputParams({
                path: _encodedPath,
                recipient: address(this),
                amountIn: amountInAfterFee,
                amountOutMinimum: _amountOutMin
            });
            amountOut = ISwapRouter(_swapRouter).exactInput{value: 0}(inputParams);
        }
        require(amountOut >= _amountOutMin, 'CSRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        // handle fee
        uint256 amountOutAfterFee = handleFee(outputToken, inputToken, amountOut, _sendPlatformFee);
        if (_to != address(this)) {
            if (isOutputETH) {
                IWETH(WETH).withdraw(amountOutAfterFee);
                TransferHelper.safeTransferETH(_to, amountOutAfterFee);
            } else {
                TransferHelper.safeTransfer(outputToken, _to, amountOutAfterFee);
            }
        }
        emit SwapOut(_to, inputToken, amountInAfterFee, amountOutAfterFee);
    }

    // Returns the amount after fee
    function handleFee(
        address _token0,
        address _token1,
        uint256 _amount,
        bool _sendPlatformFee
    ) internal returns (uint256) {
        if (!_sendPlatformFee) {
            return _amount;
        }
        uint256 feeAmount = (_amount * feePercent) / FEE_DIVISOR;
        if (_token0 == WETH) {
            IWETH(WETH).withdraw(feeAmount);
            TransferHelper.safeTransferETH(feeReceiver, feeAmount);
            return _amount - feeAmount;
        } else if (_token0 == USDC && _token1 != WETH) {
            TransferHelper.safeTransfer(_token0, feeReceiver, feeAmount);
            return _amount - feeAmount;
        } else if (_token0 == USDT && _token1 != WETH && _token1 != USDC) {
            TransferHelper.safeTransfer(_token0, feeReceiver, feeAmount);
            return _amount - feeAmount;
        } else {
            return _amount;
        }
    }
}
