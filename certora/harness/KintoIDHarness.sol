// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import { KintoID } from "src/KintoID.sol";

contract KintoIDHarness is KintoID {

    constructor(address _walletFactory, address _faucet) KintoID(_walletFactory, _faucet) {}

    function unsafeOwnerOf(uint256 tokenId) external view returns (address) {
        return _ownerOf(tokenId);
    }

    function unsafeGetApproved(uint256 tokenId) external view returns (address) {
        return getApproved(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        return _baseURI();
    }

    function nextTokenId() public view returns (uint256) {
        return _nextTokenId;
    }
}