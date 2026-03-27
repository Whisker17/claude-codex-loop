"""Event sourcing aggregate store with snapshots and optimistic concurrency."""
import threading
import json
import copy
from typing import Any, Callable, Optional
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Event:
    aggregate_id: str
    event_type: str
    data: dict
    version: int
    timestamp: datetime = field(default_factory=datetime.utcnow)


@dataclass
class Snapshot:
    aggregate_id: str
    state: dict
    version: int
    timestamp: datetime = field(default_factory=datetime.utcnow)


class EventStore:
    SNAPSHOT_INTERVAL = 50

    def __init__(self):
        self._events: dict[str, list[Event]] = {}
        self._snapshots: dict[str, Snapshot] = {}
        self._handlers: list[Callable] = []
        self._locks: dict[str, threading.Lock] = {}
        self._global_lock = threading.Lock()

    def _get_lock(self, aggregate_id: str) -> threading.Lock:
        if aggregate_id not in self._locks:
            with self._global_lock:
                if aggregate_id not in self._locks:
                    self._locks[aggregate_id] = threading.Lock()
        return self._locks[aggregate_id]

    def append(self, aggregate_id: str, events: list[dict],
               expected_version: int) -> int:
        lock = self._get_lock(aggregate_id)
        with lock:
            current_events = self._events.get(aggregate_id, [])
            current_version = len(current_events)

            if current_version != expected_version:
                raise ConcurrencyError(
                    f"Expected version {expected_version}, "
                    f"but current is {current_version}"
                )

            new_events = []
            for i, event_data in enumerate(events):
                event = Event(
                    aggregate_id=aggregate_id,
                    event_type=event_data["type"],
                    data=event_data.get("data", {}),
                    version=current_version + i + 1,
                )
                new_events.append(event)

            if aggregate_id not in self._events:
                self._events[aggregate_id] = []
            self._events[aggregate_id].extend(new_events)

            new_version = current_version + len(new_events)

            # Take snapshot if needed
            if new_version // self.SNAPSHOT_INTERVAL > current_version // self.SNAPSHOT_INTERVAL:
                state = self._rebuild_state(aggregate_id)
                self._snapshots[aggregate_id] = Snapshot(
                    aggregate_id=aggregate_id,
                    state=state,
                    version=new_version,
                )

        # Notify handlers outside the lock
        for handler in self._handlers:
            for event in new_events:
                handler(event)

        return new_version

    def get_events(self, aggregate_id: str,
                   after_version: int = 0) -> list[Event]:
        events = self._events.get(aggregate_id, [])
        return [e for e in events if e.version > after_version]

    def get_state(self, aggregate_id: str,
                  apply_fn: Callable[[dict, Event], dict]) -> tuple[dict, int]:
        snapshot = self._snapshots.get(aggregate_id)
        if snapshot:
            state = snapshot.state
            start_version = snapshot.version
        else:
            state = {}
            start_version = 0

        events = self.get_events(aggregate_id, after_version=start_version)
        for event in events:
            state = apply_fn(state, event)

        version = start_version + len(events)
        return state, version

    def _rebuild_state(self, aggregate_id: str) -> dict:
        # Rebuild from scratch for snapshot
        state = {}
        for event in self._events.get(aggregate_id, []):
            # Generic state rebuild — just accumulate events
            state[event.event_type] = state.get(event.event_type, 0) + 1
            state["last_event"] = event.data
        return state

    def register_handler(self, handler: Callable):
        self._handlers.append(handler)


class ConcurrencyError(Exception):
    pass
