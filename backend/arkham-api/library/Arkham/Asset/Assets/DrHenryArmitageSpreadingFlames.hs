module Arkham.Asset.Assets.DrHenryArmitageSpreadingFlames (drHenryArmitageSpreadingFlames) where

import Arkham.Asset.Cards qualified as Cards
import Arkham.Asset.Import.Lifted
import Arkham.Helpers.Modifiers
import Arkham.Projection
import Arkham.Investigator.Types (Field (..))

newtype DrHenryArmitageSpreadingFlames = DrHenryArmitageSpreadingFlames AssetAttrs
  deriving anyclass (IsAsset, HasAbilities)
  deriving newtype (Show, Eq, ToJSON, FromJSON, Entity)

drHenryArmitageSpreadingFlames :: AssetCard DrHenryArmitageSpreadingFlames
drHenryArmitageSpreadingFlames = ally DrHenryArmitageSpreadingFlames Cards.drHenryArmitageSpreadingFlames (3, 3)

instance HasModifiersFor DrHenryArmitageSpreadingFlames where
  getModifiersFor (DrHenryArmitageSpreadingFlames a) = case a.controller of
    Nothing -> pure mempty
    Just iid -> do
      actions <- fieldMap InvestigatorActionsPerformed concat iid
      modified_ a iid
        $ [SkillModifier #willpower 1, SkillModifier #intellect 1]
        <> (if null actions then ActionDoesNotCauseAttacksOfOpportunity <$> [minBound ..] else [])

instance RunMessage DrHenryArmitageSpreadingFlames where
  runMessage msg (DrHenryArmitageSpreadingFlames attrs) = runQueueT $ case msg of
    _ -> DrHenryArmitageSpreadingFlames <$> liftRunMessage msg attrs
