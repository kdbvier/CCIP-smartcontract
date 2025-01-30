// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "divide by zero"); // Solidity automatically throws when dividing by 0
        return a / b;
    }
}
// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: APPROVE_FAILED"
        );
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FAILED"
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FROM_FAILED"
        );
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }
}

interface IUniswapV2Pair {
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IDexFactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint value
    ) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

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

interface ISwapRouter {
    function exactInput(
        Structs.ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);
    function exactInput(
        Structs.ExactInputParamsWithDeadline calldata params
    ) external payable returns (uint256 amountOut);
}

interface IMessageTransmitter {
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success);
}
interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 _nonce);
}

contract CCTPSwap is Ownable, ReentrancyGuard {

    using SafeMath for uint256;
    IMessageTransmitter public messageTransmitter;
    ITokenMessenger public tokenMessenger;

    address public immutable USDC;
    address public immutable WETH;
    address public executor;
    uint24 public constant FEE_DIVISOR = 10000;
    error FailedCall();

    struct CallStruct {
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        uint256 deadline;
        bool swapWithDeadline;
        address factoryOrSwapRouter;
        bytes encodedPath; // Array of fees for each hop
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "not executor");
        _;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "CSRouter: EXPIRED");
        _;
    }

    //////////================= Events ====================================================
    event SwapFromUSDC(
        address indexed receiver,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );

    event SwapToUSDCAndBurn(string indexed receiver, string indexed token);

    constructor(
        address _weth,
        address _executor,
        address _usdc,
        address _transmitter,
        address _messenger
    ) Ownable(msg.sender) {
        executor = _executor;
        USDC = _usdc;
        WETH = _weth;
        messageTransmitter = IMessageTransmitter(_transmitter);
        tokenMessenger = ITokenMessenger(_messenger);
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "CSRouter: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "CSRouter: ZERO_ADDRESS");
    }

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        require(amountIn > 0, "CSRouter: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "CSRouter: INSUFFICIENT_LIQUIDITY"
        );
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair

    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to,
        address factory
    ) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(
                IDexFactory(factory).getPair(input, output)
            );
            uint amountInput;
            uint amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint reserve0, uint reserve1, ) = pair.getReserves();
                (uint reserveInput, uint reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(
                    reserveInput
                );
                amountOutput = getAmountOut(
                    amountInput,
                    reserveInput,
                    reserveOutput
                );
            }
            (uint amount0Out, uint amount1Out) = input == token0
                ? (uint(0), amountOutput)
                : (amountOutput, uint(0));
            address to = i < path.length - 2
                ? IDexFactory(factory).getPair(output, path[i + 2])
                : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapFromUSDC(
        bytes calldata _message,
        bytes calldata _attestation,
        CallStruct[] calldata _calls,
        address _to,
        bool isNativeOut
    ) public nonReentrant onlyExecutor {
        uint256 beforeSending = IERC20(USDC).balanceOf(address(this));
        require(
            messageTransmitter.receiveMessage(_message, _attestation),
            "receiveMessage() failed"
        );
        uint256 afterSending = IERC20(USDC).balanceOf(address(this));
        // USDC -> Token
        uint256 initialAmountIn = afterSending - beforeSending;
        uint256 amountIn = initialAmountIn;
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        
        tokenIn = _calls[0].path[0];
        require(tokenIn == USDC, "Invalid input token");
        for (uint256 i = 0; i<_calls.length; i++) {
            CallStruct memory swapData = _calls[i];
            tokenOut = _calls[i].path[1];
            if (swapData.encodedPath.length == 0) {
                amountOut = swapV2(
                    amountIn,
                    swapData.amountOutMin,
                    swapData.path,
                    swapData.factoryOrSwapRouter
            );
            } else {
                amountOut = swapV3(
                    amountIn,
                    swapData.amountOutMin,
                    swapData.path,
                    swapData.deadline,
                    swapData.swapWithDeadline,
                    swapData.factoryOrSwapRouter,
                    swapData.encodedPath
                );
            }
            amountIn = amountOut;
        }
        if (isNativeOut) {
            require(tokenOut == WETH, "CSRouter: Invalid output token");
            IWETH(WETH).withdraw(amountOut);
            TransferHelper.safeTransferETH(_to, amountOut);
        } else {
            TransferHelper.safeTransfer(tokenOut, _to, amountOut);
        }
        emit SwapFromUSDC(_to, tokenOut, initialAmountIn, amountOut);
    }
    function swapToUSDCAndBurn(
        CallStruct[] calldata _calls,
        bool isNativeIn,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        string memory finalReceiver, // This will be
        string memory finalToken
    ) external payable nonReentrant {
        uint256 amountOut;
        uint256 amountIn;
        address tokenIn;
        address tokenOut;
        CallStruct memory swapData = _calls[0];
        tokenIn = swapData.path[0];
        tokenOut = swapData.path[1];
        if (!isNativeIn) {
            TransferHelper.safeTransferFrom(
                tokenIn,
                msg.sender,
                address(this),
                swapData.amountIn
            );
        } else {
            require(tokenIn == WETH, "Invalid token address");
            require(swapData.amountIn == msg.value, "Invalid eth amount");
            IWETH(WETH).deposit{value: msg.value}();
        }
        amountIn = swapData.amountIn;
        for (uint256 i = 0; i<_calls.length; i++) {
            swapData = _calls[i];
            tokenOut = _calls[i].path[1];
            if (swapData.encodedPath.length == 0) {
                amountOut = swapV2(
                    amountIn,
                    swapData.amountOutMin,
                    swapData.path,
                    swapData.factoryOrSwapRouter
                );
            } else {
                amountOut = swapV3(
                    amountIn,
                    swapData.amountOutMin,
                    swapData.path,
                    swapData.deadline,
                    swapData.swapWithDeadline,
                    swapData.factoryOrSwapRouter,
                    swapData.encodedPath
                );
            }
            amountIn = amountOut;
        }
        require(tokenOut == USDC, "CSRouter: Invalid output token");
        TransferHelper.safeApprove(USDC, address(tokenMessenger), amountOut);
        tokenMessenger.depositForBurn(
            amountOut,
            destinationDomain,
            mintRecipient,
            USDC
        );
        emit SwapToUSDCAndBurn(finalReceiver, finalToken);
    }
    function swapV2(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address factory
    ) internal returns (uint256 amountOut) {
        address tokenIn = path[0];
        address tokenOut = path[1];
        if (tokenIn == tokenOut) {
            amountOut = amountIn;
            return amountOut;
        }
        address pairContract = IDexFactory(factory).getPair(path[0], path[1]);
        uint256 balanceFinalTokenBefore = IERC20(tokenOut).balanceOf(
            address(this)
        );
        TransferHelper.safeTransfer(tokenIn, pairContract, amountIn);
        _swapSupportingFeeOnTransferTokens(path  , address(this), factory);
        uint256 balanceFinalTokenAfter = IERC20(tokenOut).balanceOf(
            address(this)
        );
        amountOut = balanceFinalTokenAfter - balanceFinalTokenBefore;
        require(
            amountOut >= amountOutMin,
            "CSRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapV3(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        uint256 deadline,
        bool useDeadline,
        address swapRouter,
        bytes memory encodedPath
    ) internal ensure(deadline) returns (uint256 amountOut) {
        if(path[0] == path[1]) {
            amountOut = amountIn;
            return amountOut;
        }
        IERC20(path[0]).approve(swapRouter, amountIn);
        if (useDeadline) {
            Structs.ExactInputParamsWithDeadline memory inputParams = Structs
                .ExactInputParamsWithDeadline({
                    path: encodedPath,
                    recipient: address(this),
                    deadline: deadline,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin
                });
            amountOut = ISwapRouter(swapRouter).exactInput(inputParams);
        } else {
            Structs.ExactInputParams memory inputParams = Structs
                .ExactInputParams({
                    path: encodedPath,
                    recipient: address(this),
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin
                });
            amountOut = ISwapRouter(swapRouter).exactInput(inputParams);
        }
        require(
            amountOut >= amountOutMin,
            "CSRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function setExecutor(address _newExecutor) external onlyOwner {
        executor = _newExecutor;
    }

    function recoverStuckTokens(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner(), amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
