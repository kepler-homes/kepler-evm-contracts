
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) ERC20(name, symbol) Ownable() {
        if (supply > 0) {
            _mint(msg.sender, supply);
        }
    }

    function getOwner() public view returns (address) {
        return owner();
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
