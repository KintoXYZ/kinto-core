// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin-5.0.1/contracts/utils/cryptography/EIP712.sol";
import {ERC721Votes} from "@openzeppelin-5.0.1/contracts/token/ERC721/extensions/ERC721Votes.sol";

contract NioGuardians is ERC721, Ownable, EIP712, ERC721Votes {
    error OnlyMintOrBurn();
    error NoDelegate();

    constructor(address initialOwner)
        ERC721("Nio Guardians", "NIO")
        Ownable(initialOwner)
        EIP712("Nio Guardians", "1")
    {}

    function mint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
        // delegate the votes on a mint to a holder
        _delegate(to, to);
    }

    function burn(uint256 tokenId) public onlyOwner {
        _burn(tokenId);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Votes)
        returns (address)
    {
        address from = super._update(to, tokenId, auth);

        if (from != address(0) && to != address(0)) revert OnlyMintOrBurn();

        return from;
    }

    function delegate(address) public pure override {
        revert NoDelegate();
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Votes) {
        super._increaseBalance(account, value);
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
