// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {console} from "forge-std/console.sol";

contract TokenStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    error CannotStakeZero();
    error InsufficientAllowance();
    error InsufficientBalance();
    error NoRewardsToClaim();
    error AlreadyClaimedThisCycle();
    error CycleNotEnded();
    error RewardAmountMustBeGreaterThanZero();
    error InsufficientRewards();
    error InvalidCycleState();
    error InvalidAddress();
    error InvalidCycle();
    error NoStakedTokens();
    error AmountTooSmall();
    error CycleNotOpen();
    error CycleAlreadyOpen();

    IERC20 public immutable _RVT; // RVT token for staking and rewards

    uint256 public constant _CYCLE_DURATION = 15 days; // Approx 15 days
    uint256 public constant _MAX_CYCLES = 15; // 225 days
    uint256 public constant _MIN_STAKE_AMOUNT = 1e18;

    // Cycle states
    enum CycleState { OPEN, RUNNING, ENDED, INITIAL }

    struct UserStake {
        uint256 amount; // Staked RVT
        uint256 startCycle; // Cycle when user started staking
    }

    struct Cycle {
        uint256 pool; // Reward pool for cycle
        uint256 supply; // Total staked RVT for cycle
        uint256 startTime; // Start time of cycle
        uint256 endTime; // End time of cycle
        CycleState state; // State of cycle
    }

    mapping(uint256 => Cycle) public _cycles; // Reward pool per cycle
    mapping(address => UserStake) public _stakes;
    mapping(address => mapping(uint256 => bool)) public _claimedCycles;

    uint256 public _currentCycle; // Current cycle number
    uint256 public _totalRewardsDistributed; // Total rewards distributed across all cycles

    event Staked(address indexed user, uint256 amount, uint256 cycle);
    event Withdrawn(address indexed user, uint256 amount, uint256 cycle);
    event RewardClaimed(address indexed user, uint256 reward, uint256 cycle);
    event NewCycleOpened(uint256 cycle, uint256 rewardAmount, uint256 timestamp);
    event NewCycleStarted(uint256 cycle, uint256 rewardAmount, uint256 timestamp);
    event RewardPoolUpdated(uint256 rewardAmount, uint256 cycle);

    constructor(address _rvt) Ownable(msg.sender) {
        if(_rvt == address(0)) revert InvalidAddress();
        _RVT = IERC20(_rvt);
        _currentCycle = 0;
        _cycles[_currentCycle].state = CycleState.INITIAL;
    }

    function getCurrentCycle() public view returns (Cycle memory) {
        return _cycles[_currentCycle];
    }

    function currentIsOpen() public view returns (bool) {
        return _cycles[_currentCycle].state == CycleState.OPEN;
    }

    function currentIsEnded() public view returns (bool) {
        return _cycles[_currentCycle].state == CycleState.ENDED;
    }

    function currentIsEndedByTime() public view returns (bool) {
        return _cycles[_currentCycle].endTime < block.timestamp;
    }

    function getCycle(uint256 _cycle) public view returns (Cycle memory) {
        if (_cycle > _currentCycle) revert InvalidCycle();
        return _cycles[_cycle];
    }

    function getStakes(address _account) public view returns (UserStake memory) {
        return _stakes[_account];
    }

    function getStakeProportion(address _account, uint256 _cycle) public view returns (uint256) {
        if (_cycles[_cycle].supply == 0) return 0;
        return (_stakes[_account].amount * 1e48) / _cycles[_cycle].supply; // Higher precision
    }

    function getCycleReward(address _account, uint256 _cycle) public view returns (uint256) {
        if (_cycle > _currentCycle || _stakes[_account].amount == 0) return 0;
        if (_cycles[_cycle].supply == 0 || _cycles[_cycle].pool == 0) return 0;
        if (_claimedCycles[_account][_cycle]) return 0;
        return (_cycles[_cycle].pool * getStakeProportion(_account, _cycle)) / 1e48; // Higher precision
    }

    // The users will have more than 6 months to claim their rewards, if they dont claim it the rewards will be lost, so the RVT will be locked forever
    function getTotalOldCycleRewards(address _account) public view returns (uint256) {
        uint256 totalRewards = 0;
        uint256 initialCycle = _currentCycle > _MAX_CYCLES ? _currentCycle - _MAX_CYCLES + 1 : 1;
        uint256 endCycle = _currentCycle > 0 ? _currentCycle - 1 : 0;

        for(uint256 i = initialCycle; i <= endCycle; i++) {
            if(_claimedCycles[_account][i]) continue;
            totalRewards += getCycleReward(_account, i);
        }

        return totalRewards;
    }

    function stake(uint256 _amount) external nonReentrant whenNotPaused {
        if (_amount == 0) revert CannotStakeZero();
        if (_amount < _MIN_STAKE_AMOUNT) revert AmountTooSmall();
        if (_cycles[_currentCycle].state != CycleState.OPEN) revert CycleNotOpen();
        if (_RVT.allowance(msg.sender, address(this)) < _amount) revert InsufficientAllowance();
        if(_stakes[msg.sender].startCycle == 0) _stakes[msg.sender].startCycle = _currentCycle;

        _cycles[_currentCycle].supply += _amount;
        _stakes[msg.sender].amount += _amount;

        _RVT.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount, _currentCycle);
    }

    // Withdraw staked RVT and claim rewards
    function withdraw() public nonReentrant whenNotPaused {
        if (!currentIsOpen()) revert CycleNotOpen();
        if (_stakes[msg.sender].startCycle == 0) revert NoStakedTokens();

        claimOldCycleRewards();

        uint256 userAmount = _stakes[msg.sender].amount;
        _cycles[_currentCycle].supply -= userAmount;
        _stakes[msg.sender].amount = 0;
        _stakes[msg.sender].startCycle = 0;

        _RVT.safeTransfer(msg.sender, userAmount);
        emit Withdrawn(msg.sender, userAmount, _currentCycle);
    }

    function claimCycleRewards(uint256 _cycle) public nonReentrant whenNotPaused  {
        if (_cycle >= _currentCycle) revert InvalidCycle();
        if (_claimedCycles[msg.sender][_cycle]) revert AlreadyClaimedThisCycle();
        if (_stakes[msg.sender].amount == 0) revert NoStakedTokens();

        uint256 reward = getCycleReward(msg.sender, _cycle);
        if (reward == 0) revert NoRewardsToClaim();

        _claimedCycles[msg.sender][_cycle] = true;
        _totalRewardsDistributed += reward;

        _RVT.safeTransfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward, _cycle);
    }

    function claimOldRewards() public nonReentrant whenNotPaused {
        uint256 totalRewards = claimOldCycleRewards();
        if (totalRewards == 0) revert NoRewardsToClaim();
        emit RewardClaimed(msg.sender, totalRewards, _currentCycle);
    }

    function claimOldCycleRewards() private returns (uint256) {
        uint256 totalRewards = 0;
        uint256 initialCycle = _currentCycle > _MAX_CYCLES ? _currentCycle - _MAX_CYCLES + 1 : 1;
        uint256 endCycle = _currentCycle > 0 ? _currentCycle - 1 : 0;

        for (uint256 i = initialCycle; i <= endCycle; i++) {
            if (_claimedCycles[msg.sender][i]) continue;
            totalRewards += getCycleReward(msg.sender, i);
            _claimedCycles[msg.sender][i] = true;
        }

        if (totalRewards != 0) _RVT.safeTransfer(msg.sender, totalRewards);
        return totalRewards;
    }

    function openInitialCycle(uint256 _rewardAmount) public onlyOwner whenNotPaused {
        if(_cycles[_currentCycle].state != CycleState.INITIAL) revert InvalidCycleState();
        if (_rewardAmount == 0) revert RewardAmountMustBeGreaterThanZero();

        _currentCycle++;
        _cycles[_currentCycle].state = CycleState.OPEN;
        _cycles[_currentCycle].startTime = 0;
        _cycles[_currentCycle].endTime = 0;
        _cycles[_currentCycle].supply = 0;
        _cycles[_currentCycle].pool = _rewardAmount;

        _RVT.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        emit NewCycleOpened(_currentCycle, _rewardAmount, block.timestamp);
        emit RewardPoolUpdated(_rewardAmount, _currentCycle);
    }

    function endAndOpenCycle(uint256 _rewardAmount) public onlyOwner whenNotPaused {
        if( _cycles[_currentCycle].state != CycleState.RUNNING) revert InvalidCycleState();
        if (!currentIsEndedByTime()) revert CycleNotEnded();
        if (_rewardAmount == 0) revert RewardAmountMustBeGreaterThanZero();

        _currentCycle++;
        _cycles[_currentCycle - 1].state = CycleState.ENDED;
        _cycles[_currentCycle].state = CycleState.OPEN;
        _cycles[_currentCycle].startTime = 0;
        _cycles[_currentCycle].endTime = 0;
        _cycles[_currentCycle].pool = _rewardAmount;
        // This is valid because no ones can withdraw or stake while the current cycle is running
        // So the supply only changes while the cycle is open
        _cycles[_currentCycle].supply = _cycles[_currentCycle - 1].supply;

        _RVT.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        emit NewCycleOpened(_currentCycle, _rewardAmount, block.timestamp);
        emit RewardPoolUpdated(_rewardAmount, _currentCycle);
    }

    // Owner starts new cycle and adds rewards
    function startNewCycle() external onlyOwner whenNotPaused {
        if (_cycles[_currentCycle].state != CycleState.OPEN) revert InvalidCycleState();
        if (_cycles[_currentCycle].pool == 0) revert RewardAmountMustBeGreaterThanZero();
        if(_RVT.balanceOf(address(this)) < _cycles[_currentCycle].supply + _cycles[_currentCycle].pool) revert InsufficientRewards();

        _cycles[_currentCycle].startTime = block.timestamp;
        _cycles[_currentCycle].endTime = block.timestamp + _CYCLE_DURATION;
        _cycles[_currentCycle].state = CycleState.RUNNING;

        emit NewCycleStarted(_currentCycle, _cycles[_currentCycle].pool, block.timestamp);
    }

    // Owner can pause/unpause
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}