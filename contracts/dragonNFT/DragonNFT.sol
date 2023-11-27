// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// * tokens
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// * accesses
import "@openzeppelin/contracts/access/Ownable.sol";
import "../operator/interface/IOperator.sol";

// * utils
import "@openzeppelin/contracts/utils/Counters.sol";

// * libraries
import "./library/DragonNFTLib.sol";

contract DragonNFT is ERC721, Ownable {
    using DragonNFTLib for uint256;
    using Counters for Counters.Counter;

    IOperator private immutable operator;
    Counters.Counter private _tokenIdCounter;
    
    // TokenID에 따른 드래곤 정보를 저장하는 매핑
    mapping(uint256 => DragonNFTLib.Dragon) public dragons;

    // 희귀도별 경험치 획득량, 확률 가중치, 데미지
    uint32[] private rarityBasedExperience = [10, 12, 14, 16, 18, 20];
    uint8[] private speciesCountPerRarity = [8, 5, 4, 3, 2, 1];
    uint64[] private rarityBasedDamage = [50, 100, 170, 300, 450, 700];

    // 최고 레벨
    uint8 immutable MAX_LEVEL;

    // 레벨업 하는데 필요한 경험치 배열
    uint32[] public xpToLevelUp;

    event NewDragonBorn(uint256 _tokenId, DragonNFTLib.Gender _gender, DragonNFTLib.Rarity _rarity, DragonNFTLib.Species _specie, uint64 _damage, uint256 _lastInteracted, uint32 _xpPerSec);
    event DragonExperienceGained(uint256 _tokenId, uint8 _level, uint32 _xp, uint32 _xpToAdd);
    event DragonLevelUp(uint256 _tokenId, uint8 _level, uint32 _xp, uint64 _damage);
    event DragonLevelXPAdjusted(uint8 level, uint32 previousXP, uint32 newXP);

    modifier onlyOperator() {
        require(operator.isOperator(msg.sender), "DragonNFT : Not a valid operator");
        _;
    }

    // _xpToLevelUp 비선형적으로 계산해서 인자값으로 받습니다.
    constructor(uint8 _maxLevel, uint32[] memory _xpToLevelUp, address _operator) ERC721("Dragon Rearing","DR") {
        require(_maxLevel == _xpToLevelUp.length, "DragonNFT : Max level and xp array length must match");
        MAX_LEVEL = _maxLevel;
        xpToLevelUp = _xpToLevelUp;
        operator = IOperator(_operator);
    }

    // 신규 드래곤을 mint하는 함수입니다.
    function mintNewDragon(address requester, uint256[] memory _randomWords) external onlyOperator {
        DragonNFTLib.Gender gender = _randomWords[0].determineGender();
        DragonNFTLib.Rarity rarity = _randomWords[1].determineRarity();
        DragonNFTLib.Species specie = _randomWords[2].determineSpecies(rarity, speciesCountPerRarity);
        uint64 damage = _randomWords[3].determineDamage(rarity, rarityBasedDamage);
        uint32 xpPerSec = DragonNFTLib.determineExperience(rarity, rarityBasedExperience);

        createDragon(requester, gender, rarity, specie, damage, xpPerSec);
    }

    // 드래곤 NFT를 생성합니다.
    function createDragon(address _to, DragonNFTLib.Gender _gender, DragonNFTLib.Rarity _rarity, DragonNFTLib.Species _specie, uint64 _damage, uint32 _xpPerSec) public onlyOperator returns(uint256 tokenId) {
        uint256 _tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        dragons[_tokenId] = DragonNFTLib.Dragon({
            gender : _gender,
            rarity : _rarity,
            specie : _specie,
            level : 1,
            xp : 0,
            damage : _damage,
            lastInteracted : block.timestamp, 
            xpPerSec : _xpPerSec
        });

        _safeMint(_to, _tokenId);
        emit NewDragonBorn(_tokenId, _gender, _rarity, _specie, _damage, block.timestamp, _xpPerSec);
        return tokenId;
    }

    // 현재까지 축적된 드래곤의 경험치를 증가시킵니다.
    function addExperience(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "DragonNFT : Caller is not the owner");
        DragonNFTLib.Dragon storage dragon = dragons[tokenId];
        require(dragon.level < MAX_LEVEL, "DragonNFT : Dragon at max level");

        uint256 currentTime = block.timestamp;
        uint256 secondsPassed = currentTime - dragon.lastInteracted;
        require(secondsPassed > 0, "DragonNFT : No time passed since last interaction");

        uint32 xpToAdd = uint32(secondsPassed * dragon.xpPerSec);
        uint32 xpRequiredForNextLevel = xpToLevelUp[dragon.level - 1];

        // 레벨업을 위한 경험치가 충분한지 확인합니다.
        if (dragon.xp + xpToAdd >= xpRequiredForNextLevel) {
            uint8 levelsGained = 0;
            uint32 xpRemaining = dragon.xp + xpToAdd;

            // 드래곤의 경험치가 다음 레벨업에 필요한 경험치 이상인지를 반복적으로 확인하고, 필요한 경우 드래곤의 레벨을 올립니다.
            while (xpRemaining >= xpRequiredForNextLevel && dragon.level + levelsGained < MAX_LEVEL) {
                xpRemaining -= xpRequiredForNextLevel;
                levelsGained++;
                if (dragon.level + levelsGained < MAX_LEVEL) {
                    xpRequiredForNextLevel = xpToLevelUp[dragon.level + levelsGained - 1];
                }
            }

            dragon.level += levelsGained;
            dragon.xp = xpRemaining;
            dragon.damage += dragon.damage * levelsGained / 5;
            dragon.lastInteracted = currentTime;

            // 레벨업 이벤트 발생
            emit DragonLevelUp(tokenId, dragon.level, dragon.xp, dragon.damage);
        } else {
            dragon.xp += xpToAdd;
            dragon.lastInteracted = currentTime;
        }

        emit DragonExperienceGained(tokenId, dragon.level, dragon.xp, xpToAdd);
    }

    // 레벨에 따라 필요한 XP를 재설정합니다.
    function setXpToLevelUp(uint8 level, uint32 xpRequired) external onlyOwner {
        require(level < MAX_LEVEL, "DragonNFT : Invalid level");
        uint32 previousXP = xpToLevelUp[level];
        xpToLevelUp[level] = xpRequired;
        emit DragonLevelXPAdjusted(level, previousXP, xpRequired);
    }

    // 드래곤 정보를 반환합니다.
    function getDragonInfo(uint256 tokenId) external view returns(DragonNFTLib.Dragon memory dragonInfo) {
        return dragons[tokenId];
    }

    // 드래곤의 희귀도별 경험치 획득량을 반환합니다.
    function getRarityBasedExperience() external view returns (uint32[] memory) {
        return rarityBasedExperience;
    }

    // 드래곤의 희귀도별 확률 가중치를 반환합니다.
    function getSpeciesCountPerRarity() external view returns (uint8[] memory) {
        return speciesCountPerRarity;
    }

    // 드래곤의 희귀도별 데미지를 반환합니다.
    function getRarityBasedDamage() external view returns (uint64[] memory) {
        return rarityBasedDamage;
    }
}