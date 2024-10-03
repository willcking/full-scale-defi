pragma solidity ^0.8.20;

import "./interface/IAdmin.sol";

contract Admin is IAdmin {
    address[] public admins;

    mapping(address => bool) public isAdmin;

    modifier onlyAdmin {
        require(isAdmin[msg.sender], "only admin can call");
        _;
    }

    function init(address[] memory _admins) external {
        require(_admins.length > 0, "at least one admin");
        for(uint i = 0; i < _admins.length; i++) {
            admins.push(_admins[i]);
            isAdmin[_admins[i]] = true;
        }
    }

    function addAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "admin can't be 0");
        require(!isAdmin[newAdmin], "the address arleady is admin");
        admins.push(newAdmin);
        isAdmin[newAdmin] = true;
    }

    function removeAdmin(address _adminAddress) external onlyAdmin {
        require(isAdmin[_adminAddress]);
        require(admins.length > 1, "can't remove all admins since contract becomes unusable");
        uint i =0;

        while(admins[i] != _adminAddress){
            if(i == admins.length){
                revert("the admin address can't exist");
            }
        }

        admins[i] = admins[admins.length-1];
        isAdmin[_adminAddress] = false;
        admins.pop();
    }

    function getAllAdmins() external view returns(address [] memory){
        return admins;
    }
}