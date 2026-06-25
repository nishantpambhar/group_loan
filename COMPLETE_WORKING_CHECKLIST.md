# Group Loan App - Complete Working Checklist

Final features included:

1. Admin / Member PIN login on app start.
2. Firebase cloud sync using Group Code.
3. Admin full add/edit/delete access.
4. Member view-only access.
5. Monthly collection calculation.
6. Member-wise penalty calculation.
7. Dashboard calculation:
   - Cash in hand
   - Members
   - Loans out
   - Interest expected
   - Interest received / credit
   - Interest due
   - Penalty accrued
8. Loan calculation:
   - Flat interest = amount × rate × months / 1200
   - Total payable = principal + interest
   - EMI = total payable / months
   - Paid / remaining balance
   - Loan overdue penalty
   - Move to paid history without deleting interest/payment data
9. VC Year Report like Excel sheet:
   - Name
   - Jan-Dec collection
   - Penalty
   - VC(%)
   - VC(DR)
   - VC(CR)
   - Total
   - Interest Due
   - Interest Paid
   - Percentile
   - Additional Notes
10. PDF generation with table format.
11. WhatsApp PDF file share.
12. Android GitHub Actions APK/AAB build workflow.

Firebase required:
- Firestore Database enabled
- Authentication Anonymous enabled

Phone Auth/OTP is not required.
