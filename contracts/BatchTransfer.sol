// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

// Minimal interface of ERC20  
interface IERC20 {  
    function transfer(address recipient, uint256 amount) external returns (bool);  
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}  

contract BatchTransfer {  
    function batchTransfer(address token, address[] calldata recipients, uint256[] calldata amounts) external {  
        require(recipients.length == amounts.length, "Recipients and amounts length mismatch");  
        
        IERC20 erc20Token = IERC20(token);  

        for (uint256 i = 0; i < recipients.length; i++) {  
            require(erc20Token.transferFrom(msg.sender, recipients[i], amounts[i]), "Transfer failed");  
        }  
    }  
}  