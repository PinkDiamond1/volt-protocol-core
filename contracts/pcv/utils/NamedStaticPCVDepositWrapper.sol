pragma solidity ^0.8.4;

import "../IPCVDepositBalances.sol";
import "../../Constants.sol";
import "../../refs/CoreRef.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
  @notice a contract to report static PCV data to cover PCV not held with a reliable oracle or on-chain reading 
  @author Fei Protocol

  Returns PCV in USD terms
*/
contract NamedStaticPCVDepositWrapper is IPCVDepositBalances, CoreRef {
    using SafeCast for *;

    // -------------- Events ---------------
    /// @notice event to update fei and usd balance
    event BalanceUpdate(uint256 oldBalance, uint256 newBalance, uint256 oldFEIBalance, uint256 newFEIBalance);

    /// @notice event to remove a deposit
    event DepositRemoved(uint256 index);
    
    /// @notice event to add a new deposit
    event DepositAdded(uint256 index, string indexed depositName);

    /// @notice event emitted when a deposit is edited
    event DepositEdited(uint256 index, string indexed depositName);

    /// @notice struct to store info on each PCV Deposit
    struct DepositInfo {
        string depositName;
        uint256 usdAmount; /// USD equivalent in this deposit, not including FEI value
        uint256 feiAmount; /// amount of FEI in this deposit
        uint256 underlyingTokenAmount; /// amount of underlying token in this deposit
        address underlyingToken; /// address of the underlying token this deposit is reporting
    }

    /// @notice a list of all pcv deposits
    DepositInfo[] public pcvDeposits;

    /// @notice the PCV balance
    uint256 public override balance;

    /// @notice the reported FEI balance
    uint256 public feiReportBalance;

    constructor(address _core, DepositInfo[] memory newPCVDeposits) CoreRef(_core) {

        // Uses oracle admin to share admin with CR oracle where this contract is used
        _setContractAdminRole(keccak256("ORACLE_ADMIN_ROLE"));

        // add all pcv deposits
        for (uint256 i = 0; i < newPCVDeposits.length; i++) {
            _addDeposit(newPCVDeposits[i]);
        }
    }

    // ----------- Helper methods to change state -----------

    /// @notice helper method to delete a PCV deposit
    function _removeDeposit(uint256 index) internal {
        if (pcvDeposits.length == 0) { return; }

        DepositInfo storage removePCVDeposit = pcvDeposits[index];

        uint256 depositBalance = removePCVDeposit.usdAmount;
        uint256 feiDepositBalance = removePCVDeposit.feiAmount;

        uint256 oldBalance = balance;
        uint256 oldFeiReportBalance = feiReportBalance;

        uint256 lastIndex = pcvDeposits.length - 1;

        if (lastIndex != index) {
            DepositInfo storage lastvalue = pcvDeposits[lastIndex];

            // Move the last value to the index where the value to delete is
            pcvDeposits[index] = lastvalue;
        }
        // Delete the slot where the moved value was stored
        pcvDeposits.pop();

        balance -= depositBalance;
        feiReportBalance -= feiDepositBalance;

        emit BalanceUpdate(oldBalance, balance, oldFeiReportBalance, feiReportBalance);
        emit DepositRemoved(index);
    }

    /// @notice helper method to add a PCV deposit
    function _addDeposit(DepositInfo memory newPCVDeposit) internal {
        require(newPCVDeposit.feiAmount > 0 || newPCVDeposit.usdAmount > 0, "NamedStaticPCVDepositWrapper: must supply either fei or usd amount");

        uint256 oldBalance = balance;
        uint256 oldFEIBalance = feiReportBalance;

        balance += newPCVDeposit.usdAmount;
        feiReportBalance += newPCVDeposit.feiAmount;
        pcvDeposits.push(newPCVDeposit);

        emit DepositAdded(pcvDeposits.length - 1, newPCVDeposit.depositName);
        emit BalanceUpdate(oldBalance, balance, oldFEIBalance, feiReportBalance);
    }

    /// @notice helper method to edit a PCV deposit
    function _editDeposit(
        uint256 index,
        string calldata depositName,
        uint256 usdAmount,
        uint256 feiAmount,
        uint256 underlyingTokenAmount,
        address underlyingToken
    ) internal {
        DepositInfo storage updatePCVDeposit = pcvDeposits[index];

        uint256 oldBalance = balance;
        uint256 oldFEIBalance = feiReportBalance;

        balance = balance - updatePCVDeposit.usdAmount + usdAmount;
        feiReportBalance = feiReportBalance - updatePCVDeposit.feiAmount + feiAmount;

        updatePCVDeposit.usdAmount = usdAmount + updatePCVDeposit.usdAmount;
        updatePCVDeposit.depositName = depositName;
        updatePCVDeposit.underlyingTokenAmount = underlyingTokenAmount;
        updatePCVDeposit.underlyingToken = underlyingToken;

        emit DepositEdited(index, depositName);
        emit BalanceUpdate(oldBalance, balance, oldFEIBalance, feiReportBalance);
    }

    // ----------- Governor only state changing api -----------

    /// @notice function to add a deposit
    function addDeposit(
        DepositInfo calldata newPCVDeposit
    ) external onlyGovernorOrAdmin {
        _addDeposit(newPCVDeposit);
    }

    /// @notice function to bulk add deposits
    function bulkAddDeposits(
        DepositInfo[] calldata newPCVDeposits
    ) external onlyGovernorOrAdmin {
        for (uint256 i = 0; i < newPCVDeposits.length; i++) {
            _addDeposit(newPCVDeposits[i]);
        }
    }

    /// @notice function to edit an existing deposit
    function editDeposit(
        uint256 index,
        uint256 usdAmount,
        uint256 feiAmount,
        uint256 underlyingTokenAmount,
        string calldata depositName,
        address underlying
    ) external onlyGovernorOrAdmin {
        _editDeposit(
            index,
            depositName,
            usdAmount,
            feiAmount,
            underlyingTokenAmount,
            underlying
        );
    }

    /// @notice function to remove a PCV Deposit
    function removeDeposit(uint256 index) external onlyGovernorOrAdmin {
        _removeDeposit(index);
    }

    // ----------- Getters -----------

    /// @notice returns the current number of PCV deposits
    function numDeposits() public view returns (uint256) {
        return pcvDeposits.length;
    }

    /// @notice returns the resistant balance and FEI in the deposit
    function resistantBalanceAndFei() public view override returns (uint256, uint256) {
        return (balance, feiReportBalance);
    }

    /// @notice display the related token of the balance reported
    function balanceReportedIn() public pure override returns (address) {
        return Constants.USD;
    }
    
    /// @notice function to return all of the different tokens deposited into this contract
    function getAllUnderlying() public view returns (address[] memory) {
        uint256 totalDeposits = numDeposits();

        address[] memory allUnderlyingTokens = new address[](totalDeposits);
        for (uint256 i = 0; i < totalDeposits; i++) {
            allUnderlyingTokens[i] = pcvDeposits[i].underlyingToken;
        }

        return allUnderlyingTokens;
    }
}
