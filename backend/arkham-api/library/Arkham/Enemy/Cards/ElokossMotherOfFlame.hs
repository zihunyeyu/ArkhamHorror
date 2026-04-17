module Arkham.Enemy.Cards.ElokossMotherOfFlame (elokossMotherOfFlame) where


import Arkham.Enemy.Cards qualified as Cards
import Arkham.Enemy.Import.Lifted
import Arkham.Helpers.Modifiers
import Arkham.Helpers.GameValue

newtype ElokossMotherOfFlame = ElokossMotherOfFlame EnemyAttrs
  deriving anyclass IsEnemy
  deriving newtype (Show, Eq, ToJSON, FromJSON, Entity, HasAbilities)

instance HasModifiersFor ElokossMotherOfFlame where
  getModifiersFor (ElokossMotherOfFlame a) = do
    healthModifier <- perPlayer 5
    modifySelf a [HealthModifier healthModifier]

elokossMotherOfFlame :: EnemyCard ElokossMotherOfFlame
elokossMotherOfFlame = enemy ElokossMotherOfFlame Cards.elokossMotherOfFlame (5, Static 5, 5) (3, 3)

instance RunMessage ElokossMotherOfFlame where
  runMessage msg (ElokossMotherOfFlame attrs) = ElokossMotherOfFlame <$> runMessage msg attrs
