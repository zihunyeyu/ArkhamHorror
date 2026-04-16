module Arkham.Treachery.Cards.Downpour (downpour) where

import Arkham.Helpers.SkillTest.Lifted (beginSkillTest)
import Arkham.Investigator.Types (Field (..))
import Arkham.Message.Lifted.Choose
import Arkham.Projection
import Arkham.Token qualified as Token
import Arkham.Treachery.Cards qualified as Cards
import Arkham.Treachery.Import.Lifted hiding (beginSkillTest)

newtype Downpour = Downpour TreacheryAttrs
  deriving anyclass (IsTreachery, HasModifiersFor, HasAbilities)
  deriving newtype (Show, Eq, ToJSON, FromJSON, Entity)

downpour :: TreacheryCard Downpour
downpour = treachery Downpour Cards.downpour

instance RunMessage Downpour where
  runMessage msg t@(Downpour attrs) = runQueueT $ case msg of
    Revelation iid (isSource attrs -> True) -> do
      sid <- getRandom
      beginSkillTest sid iid (toSource attrs) iid #agility (Fixed 3)
      pure t
    FailedThisSkillTestBy _ (isSource attrs -> True) n | n > 0 -> do
      doStep n msg
      pure t
    DoStep n msg'@(FailedThisSkillTest iid (isSource attrs -> True)) | n > 0 -> do
      mLoc <- field InvestigatorLocation iid
      hasClues <- (> 0) <$> field InvestigatorClues iid
      if hasClues
        then chooseOneM iid do
          labeled "Lose 1 action" $ loseActions iid attrs 1
          labeled "Place 1 clue on your location" do
            case mLoc of
              Nothing -> pure ()
              Just loc -> moveTokens (toSource attrs) (toSource iid) (toTarget loc) Token.Clue 1
        else loseActions iid attrs 1
      doStep (n - 1) msg'
      pure t
    _ -> Downpour <$> liftRunMessage msg attrs
