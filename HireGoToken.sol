pragma solidity ^0.4.18;

import "./OpenZeppelin/MintableToken.sol";
import "./OpenZeppelin/BurnableToken.sol";

contract HireGoToken is MintableToken, BurnableToken {

    string public constant name = "HireGo";
    string public constant symbol = "HGO";
    uint32 public constant decimals = 18;

    function HireGoToken() public {
        totalSupply = 100000000E18;
        balances[owner] = totalSupply; // Add all tokens to issuer balance (crowdsale in this case)
    }

}
