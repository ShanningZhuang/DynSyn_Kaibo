from typing import List, Optional, Union
import time

import gymnasium as gym
from gymnasium.wrappers import *
from stable_baselines3.common.env_util import make_vec_env
from stable_baselines3.common.utils import set_random_seed
from stable_baselines3.common.vec_env import SubprocVecEnv, VecVideoRecorder
import numpy as np

from dynsyn.sb3_runner.wrapper import *


def create_env(
    env_name: str,
    single_env_kwargs: dict,
    wrapper_list: dict,
    env_header: Optional[str] = None,
    seed: int = 0,
    render_mode: str = "rgb_array",
):
    """
    Utility function for multiprocessed env.

    :param env_id: the environment ID
    :param num_env: the number of environments you wish to have in subprocesses
    :param seed: the inital seed for RNG
    :param rank: index of the subprocess
    """
    if env_header:
        exec(env_header, globals())

    set_random_seed(seed)
    env = gym.make(env_name, render_mode=render_mode, **single_env_kwargs)

    for wrapper_name, wrapper_args in wrapper_list.items():
        try:
            env = eval(wrapper_name)(env, **wrapper_args)
        except NameError:
            print(f"Wrapper {wrapper_name} not found!")
            raise NameError

    return env


def create_vec_env(
    env_name,
    single_env_kwargs,
    env_nums,
    env_header: Optional[str] = None,
    wrapper_list: Optional[dict] = None,
    monitor_dir: Optional[str] = None,
    monitor_kwargs: Optional[dict] = None,
    seed: int = 0,
):
    if monitor_kwargs and hasattr(monitor_kwargs, "info_keywords"):
        monitor_kwargs["info_keywords"] = tuple(monitor_kwargs["info_keywords"])

    vec_env = make_vec_env(
        create_env,
        env_kwargs={
            "env_header": env_header,
            "env_name": env_name,
            "single_env_kwargs": single_env_kwargs,
            "wrapper_list": wrapper_list or {},
            "seed": seed,
        },
        n_envs=env_nums,
        vec_env_cls=SubprocVecEnv,
        monitor_dir=monitor_dir,
        monitor_kwargs=monitor_kwargs,
    )

    return vec_env


def record_video(
    vec_norm,
    model,
    args,
    video_dir: str,
    video_ep_num: int,
    name_prefix: str = "video",
    return_frames: bool = False,
):
    env = create_vec_env(
        args.env_name,
        args.single_env_kwargs,
        1,
        env_header=args.env_header,
        wrapper_list=args.wrapper_list,
        monitor_dir=None,
        monitor_kwargs=None,
        seed=args.seed,
    )
    env.render_mode = "rgb_array"
    vec_env = VecVideoRecorder(
        env,
        video_folder=video_dir,
        record_video_trigger=lambda x: x == 0,
        video_length=10000,
        name_prefix=name_prefix,
    )

    video_frames = []

    for episode_idx in range(video_ep_num):
        done = False
        total_reward = 0
        episode_qpos = []
        episode_actions = []
        episode_ctrl = []
        obs = vec_env.reset()
        
        while not done:
            # Get qpos data from the environment
            env_qpos = vec_env.get_attr('data')[0].qpos.copy()
            action = vec_env.get_attr('data')[0].act.copy()
            ctrl = vec_env.get_attr('data')[0].ctrl.copy()
            
            episode_actions.append(action)
            episode_qpos.append(env_qpos)
            episode_ctrl.append(ctrl)
            
            obs = vec_norm.normalize_obs(obs)
            action, _ = model.predict(obs, deterministic=False)
            obs, r, done, info = vec_env.step(action)
            total_reward += r

        time_stamp = time.time()
        # Save qpos data for this episode individually
        if episode_qpos:
            episode_qpos_array = np.array(episode_qpos)
            qpos_filename = f"{name_prefix}_episode_{episode_idx}_qpos_data_{time_stamp}.npy"
            qpos_filepath = video_dir + "/" + qpos_filename
            np.save(qpos_filepath, episode_qpos_array)
            print(f"Saved episode {episode_idx} qpos data to: {qpos_filepath}")
            
        # Save action data for this episode individually
        if episode_actions:
            episode_actions_array = np.array(episode_actions)
            actions_filename = f"{name_prefix}_episode_{episode_idx}_actions_data_{time_stamp}.npy"
            actions_filepath = video_dir + "/" + actions_filename
            np.save(actions_filepath, episode_actions_array)
            print(f"Saved episode {episode_idx} actions data to: {actions_filepath}")
        
        # Save ctrl data for this episode individually
        if episode_ctrl:
            episode_ctrl_array = np.array(episode_ctrl)
            ctrl_filename = f"{name_prefix}_episode_{episode_idx}_ctrl_data_{time_stamp}.npy"
            ctrl_filepath = video_dir + "/" + ctrl_filename
            np.save(ctrl_filepath, episode_ctrl_array)
            
        video_frames.append(vec_env.video_recorder.recorded_frames)
        video_fps = vec_env.video_recorder.frames_per_sec
        print(f"Episode {episode_idx} reward: {total_reward}")

    vec_env.close()

    if return_frames:
        return video_frames, video_fps
