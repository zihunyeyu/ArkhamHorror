module Arkham.Treachery.Cards.AerialPursuit (aerialPursuit) where

import Arkham.Matcher
import Arkham.Message.Lifted.Move
import Arkham.Treachery.Cards qualified as Cards
import Arkham.Treachery.Import.Lifted

newtype AerialPursuit = AerialPursuit TreacheryAttrs
  deriving anyclass (IsTreachery, HasModifiersFor, HasAbilities)
  deriving newtype (Show, Eq, ToJSON, FromJSON, Entity)

aerialPursuit :: TreacheryCard AerialPursuit
aerialPursuit = treachery AerialPursuit Cards.aerialPursuit

instance RunMessage AerialPursuit where
  runMessage msg t@(AerialPursuit attrs) = runQueueT $ case msg of
    Revelation iid (isSource attrs -> True) -> do
      enemies <- select $ NearestEnemyTo iid NonEliteEnemy
      case enemies of
        [] -> pure ()
        (eid : _) -> do
          moveToward eid (locationWithInvestigator iid)
          isEngaged <- eid <=~> enemyEngagedWith iid
          when isEngaged do
            initiateEnemyAttack eid attrs iid
      pure t
    _ -> AerialPursuit <$> liftRunMessage msg attrs
