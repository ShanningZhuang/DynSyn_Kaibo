import gymnasium as gym
import numpy as np
import mujoco as mj
from scipy.optimize import nnls
import copy

class ActivationDirectWrapper(gym.ActionWrapper):
    def __init__(self, env):
        super().__init__(env)
        self.action_space = gym.spaces.Box(low=-1, high=1, shape=(self.env.action_space.shape[0],))
    def action(self, action):
        action = 1.0 / (1.0 + np.exp(-5.0 * (action - 0.5)))
        if hasattr(self.env, 'data'):
            if hasattr(self.env, 'actuator_filter'):
                self.env.data.act[self.env.actuator_filter] = action
            else:
                self.env.data.act = action
        else:
            self.sim.data.act = action
        return action
