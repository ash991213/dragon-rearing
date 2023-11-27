// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../dragonNFT/interface/IDragonNFT.sol";

import "./library/DragonRentalLib.sol";

contract DragonRental {
    IDragonNFT private dragonNft;

    // 드래곤 대여 정보를 저장하는 매핑
    mapping(uint256 => DragonRentalLib.DragonRental) public dragonRentals;

    event DragonRented(uint256 indexed tokenId, address indexed renter, uint256 duration);

    constructor(address _dragonNft) {
        dragonNft = IDragonNFT(_dragonNft);
    }

    // 드래곤을 대여합니다.
    function rentDragon(uint256 tokenId) external {
        require(dragonNft.ownerOf(tokenId) == msg.sender, "DragonRental : Not owner.");
        require(!dragonRentals[tokenId].isRented, "DragonRental : Already rented.");

        dragonRentals[tokenId] = DragonRentalLib.DragonRental({
            isRented : true,
            startTime : block.timestamp,
            duration : block.timestamp + 48 hours,
            renter : msg.sender
        });

        emit DragonRented(tokenId, msg.sender, block.timestamp + 48 hours);
    }

    // 특정 드래곤이 호출자에 의해 소유되었거나 현재 대여중인지 확인합니다.
    function isDragonOwnedOrRentedBySender(uint256 tokenId) external view returns (bool) {
        return getDragonRental(tokenId).isRented ?
                isRentalActive(tokenId) && isRenter(tokenId, msg.sender) :
                dragonNft.ownerOf(tokenId) == msg.sender;
    }

    // 드래곤이 대여 가능한 상태인지 확인합니다.
    function isRentalActive(uint256 tokenId) public view returns (bool) {
        DragonRentalLib.DragonRental memory rental = dragonRentals[tokenId];
        return rental.isRented && (block.timestamp - rental.startTime) <= rental.duration;
    }

    // 유저가 드래곤 대여자인지 확인합니다.
    function isRenter(uint256 tokenId, address user) internal view returns (bool) {
        DragonRentalLib.DragonRental memory rental = dragonRentals[tokenId];
        return rental.isRented && rental.renter == user;
    }

    // 드래곤 대여 정보를 반환합니다.
    function getDragonRental(uint256 tokenId) public view returns(DragonRentalLib.DragonRental memory dragonRental) {
        return dragonRentals[tokenId];
    }
}
