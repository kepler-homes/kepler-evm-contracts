// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SocialShares is OwnableUpgradeable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public subjectFeePercent;

    uint8 public constant ACTION_BUY = 1;
    uint8 public constant ACTION_SELL = 2;

    event TradeEvent(
        address trader,
        address subject,
        uint8 action,
        uint256 amount,
        uint256 price,
        uint256 afterPrice,
        uint256 protocolFee,
        uint256 subjectFee,
        uint256 supply,
        uint256 balance,
        uint256 timestamp
    );

    mapping(address => mapping(address => uint256)) public sharesBalance;

    mapping(address => uint256) public sharesSupply;

    function initialize(
        address protocolFeeDestination_,
        uint256 protocolFeePercent_,
        uint256 subjectFeePercent_
    ) public initializer {
        protocolFeeDestination = protocolFeeDestination_;
        protocolFeePercent = protocolFeePercent_;
        subjectFeePercent = subjectFeePercent_;
    }

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    function setSubjectFeePercent(uint256 _feePercent) public onlyOwner {
        subjectFeePercent = _feePercent;
    }

    function _getPrice(uint256 a) private pure returns (uint256 price) {
        return ((a - 1) * a * (2 * (a - 1) + 1)) / 6;
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : _getPrice(supply);
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : _getPrice(supply + amount);
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether) / 16000;
    }

    function getBuyPrice(address sharesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesSubject], amount);
    }

    function getSellPrice(address sharesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesSubject] - amount, amount);
    }

    function getBuyPriceAfterFee(address sharesSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(sharesSubject, amount);
        uint256 protocolFee = (price * protocolFeePercent) / 1 ether;
        uint256 subjectFee = (price * subjectFeePercent) / 1 ether;
        return price + protocolFee + subjectFee;
    }

    function getSellPriceAfterFee(address sharesSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(sharesSubject, amount);
        uint256 protocolFee = (price * protocolFeePercent) / 1 ether;
        uint256 subjectFee = (price * subjectFeePercent) / 1 ether;
        return price - protocolFee - subjectFee;
    }

    function buyShares(address sharesSubject, uint256 amount) public payable {
        uint256 supply = sharesSupply[sharesSubject];
        require(supply > 0 || sharesSubject == msg.sender, "Only the shares' subject can buy the first share");
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = (price * protocolFeePercent) / 1 ether;
        uint256 subjectFee = (price * subjectFeePercent) / 1 ether;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        uint256 balance = sharesBalance[sharesSubject][msg.sender] + amount;
        sharesBalance[sharesSubject][msg.sender] = balance;
        sharesSupply[sharesSubject] = supply + amount;
        emit TradeEvent(
            msg.sender,
            sharesSubject,
            ACTION_BUY,
            amount,
            price,
            getPrice(supply + amount, 1),
            protocolFee,
            subjectFee,
            supply + amount,
            balance,
            block.timestamp
        );
        (bool success1, ) = protocolFeeDestination.call{ value: protocolFee }("");
        (bool success2, ) = sharesSubject.call{ value: subjectFee }("");
        require(success1 && success2, "Unable to send funds");
    }

    function sellShares(address sharesSubject, uint256 amount) public payable {
        uint256 supply = sharesSupply[sharesSubject];
        require(supply > amount, "Cannot sell the last share");
        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = (price * protocolFeePercent) / 1 ether;
        uint256 subjectFee = (price * subjectFeePercent) / 1 ether;
        require(sharesBalance[sharesSubject][msg.sender] >= amount, "Insufficient shares");
        uint256 balance = sharesBalance[sharesSubject][msg.sender] - amount;
        sharesBalance[sharesSubject][msg.sender] = balance;
        sharesSupply[sharesSubject] = supply - amount;
        emit TradeEvent(
            msg.sender,
            sharesSubject,
            ACTION_SELL,
            amount,
            price,
            getPrice(supply - amount, 1),
            protocolFee,
            subjectFee,
            supply - amount,
            balance,
            block.timestamp
        );
        (bool success1, ) = msg.sender.call{ value: price - protocolFee - subjectFee }("");
        (bool success2, ) = protocolFeeDestination.call{ value: protocolFee }("");
        (bool success3, ) = sharesSubject.call{ value: subjectFee }("");
        require(success1 && success2 && success3, "Unable to send funds");
    }
}
