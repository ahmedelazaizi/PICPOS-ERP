// J1b — «حساب المشتريات» choices for the PicPos purchase form.
//
// The model lives in `domain/models` and the loader in the data layer
// (`data/repositories`), so this presentation file no longer imports
// `data/database` (D4-001 guard); the screen keeps its single import.
export '../../../data/repositories/purchase_account_choices_loader.dart'
    show loadPurchaseAccountChoices;
export '../../../domain/models/picpos_purchase_account_choices.dart';
