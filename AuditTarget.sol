// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NT547 - Lab 06 - Hop dong rieng cua MSSV 25520534. KHONG deploy len mainnet.

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract TipJar_0534 {
    address public owner;
    address public immutable module; // module tin cay co dinh luc deploy
    mapping(address => uint256) public ledger;

    event Deposited(address indexed who, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address trustedModule) {
        require(trustedModule != address(0), "zero");
        owner = msg.sender;
        module = trustedModule;
    }

    function contribute() external payable {
        ledger[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function updateOwner(address newOwner) external onlyOwner {
        require(tx.origin == owner, "not owner");
        owner = newOwner;
    }

    function rescueEth(address payable to) external onlyOwner {
        require(to != address(0), "zero");
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "rescue failed");
    }

    function redeem() external {
        uint256 amount = ledger[msg.sender];
        require(amount > 0, "empty");
        ledger[msg.sender] = 0; // Effects truoc Interactions (CEI)
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "send failed");
    }

    // slither-disable-next-line controlled-delegatecall
    function plugin(bytes calldata data) external onlyOwner {
        (bool ok, ) = module.delegatecall(data);
        require(ok, "delegatecall failed");
    }

    // slither-disable-next-line incorrect-equality
    function vaultDrained() external view returns (bool) {
        return address(this).balance == 0;
    }

    function displayDay() external view returns (uint256) {
        // slither-disable-next-line weak-prng
        return (block.timestamp / 1 days + 4) % 7;
    }
}
