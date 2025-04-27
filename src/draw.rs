use std::{
    collections::BTreeMap,
    io::{Write, stdout},
};

use crossterm::{
    ExecutableCommand, QueueableCommand,
    cursor::{self, Hide, MoveTo, Show},
    event::{Event, KeyCode, KeyEvent, KeyModifiers, poll, read},
    execute, queue,
    style::{self, Color, Print, SetForegroundColor, Stylize},
    terminal::{
        self, BeginSynchronizedUpdate, EndSynchronizedUpdate, disable_raw_mode, enable_raw_mode,
        window_size,
    },
};

use crate::state::{State, WorldEntity};

pub struct Drawer {
    commanding: bool,
    current_command: String,
}

#[derive(PartialEq)]
pub enum InputEvent {
    Quit,
    Move((i16, i16)),
    Attack(i32),
    Travel(i32),
    Pickup(i32),
    Say(String),
}

impl Drawer {
    pub fn new() -> Self {
        let mut stdout = stdout();
        enable_raw_mode().unwrap();
        execute!(stdout, SetForegroundColor(Color::White), Hide,).unwrap();
        Self {
            commanding: false,
            current_command: String::new(),
        }
    }

    pub fn fetch_events(&mut self, s: &State) -> Vec<InputEvent> {
        let mut events = vec![];
        let self_entity = s
            .entities
            .iter()
            .find(|e| Some(e.entity_id) == s.self_entity_id);
        if poll(std::time::Duration::from_secs(0)).unwrap() {
            if let Some(self_entity) = self_entity {
                let event = read().unwrap();
                let mut loc = None;
                let mut travel = false;
                let mut pickup = false;
                if let true = self.commanding {
                    match event {
                        Event::Key(KeyEvent {
                            code: KeyCode::Backspace,
                            ..
                        }) => {
                            self.current_command.pop();
                            return vec![];
                        }
                        Event::Key(KeyEvent {
                            code: KeyCode::Enter,
                            ..
                        }) => {
                            let events = vec![InputEvent::Say(self.current_command.clone())];
                            self.current_command = String::new();
                            self.commanding = false;
                            return events;
                        }
                        Event::Key(KeyEvent { code, .. }) => {
                            if let Some(c) = code.as_char() {
                                self.current_command.push(c);
                            }
                            return vec![];
                        }
                        _ => {
                            return vec![];
                        }
                    }
                }
                match event {
                    Event::Key(KeyEvent {
                        code: KeyCode::Char(':'),
                        ..
                    }) => {
                        self.current_command = String::new();
                        self.commanding = true
                    }
                    Event::Key(KeyEvent {
                        code: KeyCode::Char(','),
                        ..
                    }) => pickup = true,
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('>'),
                        ..
                    }) => travel = true,
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('<'),
                        ..
                    }) => travel = true,
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('h'),
                        ..
                    }) => loc = Some((-1, 0)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('j'),
                        ..
                    }) => loc = Some((0, 1)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('k'),
                        ..
                    }) => loc = Some((0, -1)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('l'),
                        ..
                    }) => loc = Some((1, 0)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('y'),
                        ..
                    }) => loc = Some((-1, -1)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('u'),
                        ..
                    }) => loc = Some((1, -1)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('b'),
                        ..
                    }) => loc = Some((-1, 1)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('n'),
                        ..
                    }) => loc = Some((1, 1)),
                    Event::Key(KeyEvent {
                        code: KeyCode::Char('c'),
                        modifiers,
                        ..
                    }) if modifiers & KeyModifiers::CONTROL == KeyModifiers::CONTROL => {
                        events.push(InputEvent::Quit);
                    }
                    _ => {}
                }
                if pickup == true {
                    if let Some(target) = s.entities.iter().find(|e| {
                        e.x == self_entity.x && e.y == self_entity.y && e.weight.is_some()
                    }) {
                        events.push(InputEvent::Pickup(target.entity_id));
                    }
                }
                if travel == true {
                    if let Some(target) = s
                        .entities
                        .iter()
                        .find(|e| e.x == self_entity.x && e.y == self_entity.y && e.ends.is_some())
                    {
                        events.push(InputEvent::Travel(target.entity_id));
                    }
                }
                if let Some((loc_x, loc_y)) = loc {
                    if let Some(target) = s.entities.iter().find(|e| {
                        e.x == loc_x + self_entity.x
                            && e.y == loc_y + self_entity.y
                            && e.hp.filter(|h| *h > 0).is_some()
                    }) {
                        events.push(InputEvent::Attack(target.entity_id));
                    } else {
                        events.push(InputEvent::Move((loc_x, loc_y)));
                    }
                }
            }
        }

        return events;
    }

    pub fn draw(&mut self, s: &State) {
        let mut stdout = std::io::stdout();
        execute!(stdout, BeginSynchronizedUpdate).unwrap();
        stdout
            .queue(terminal::Clear(terminal::ClearType::All))
            .unwrap();
        let mut sorted_entities: Vec<&_> = s.entities.iter().map(|e| e).collect();
        sorted_entities.sort_by(|a, b| match (a.maxhp, b.maxhp, a.entity_id, b.entity_id) {
            (_, _, entity_id, _) if Some(entity_id) == s.self_entity_id => {
                std::cmp::Ordering::Greater
            }
            (_, _, _, entity_id) if Some(entity_id) == s.self_entity_id => std::cmp::Ordering::Less,
            (Some(_), _, _, _) => std::cmp::Ordering::Greater,
            (_, Some(_), _, _) => std::cmp::Ordering::Less,
            (_, _, _, _) => std::cmp::Ordering::Equal,
        });
        for e in &sorted_entities {
            match (e.x, e.y, &e.species) {
                (x, y, Some(species)) if x >= 0 && y >= 0 => {
                    queue!(
                        stdout,
                        MoveTo(e.x as u16, e.y as u16),
                        SetForegroundColor(match (e.entity_id, e.species.as_deref(), e.hp) {
                            (_, _, Some(hp)) if hp <= 0 => Color::Red,
                            (eid, _, _) if Some(eid) == s.self_entity_id => Color::Cyan,
                            (_, Some("snake"), _) => Color::Green,
                            (_, _, _) => Color::White,
                        }),
                        Print(match (species.as_str(), e.hp) {
                            (_, Some(hp)) if hp <= 0 => "%",
                            ("human", _) => "@",
                            ("door", _) => "║",
                            ("snake", _) => "s",
                            ("floor", _) => "+",
                            ("wall", _) => "#",
                            ("upstair", _) => "<",
                            _ => "?",
                        })
                    )
                    .unwrap();
                }
                _ => {}
            }
            if Some(e.entity_id) == s.self_entity_id {
                match (e.command_x, e.command_y, &e.command_type) {
                    (Some(x), Some(y), Some(command_type)) if command_type == "move" => {
                        queue!(
                            stdout,
                            MoveTo((e.x + x) as u16, (e.y + y) as u16),
                            SetForegroundColor(match e.entity_id {
                                eid if Some(eid) == s.self_entity_id => Color::Cyan,
                                _ => Color::White,
                            }),
                            Print(match (x, y, command_type.as_ref()) {
                                (_, _, "attack") => "X",
                                (1, 0, _) => "→",
                                (0, 1, _) => "↓",
                                (-1, 0, _) => "←",
                                (0, -1, _) => "↑",
                                (-1, -1, _) => "↖",
                                (1, -1, _) => "↗",
                                (1, 1, _) => "↘",
                                (-1, 1, _) => "↙",
                                _ => "?",
                            })
                        )
                        .unwrap();
                    }
                    _ => {}
                }
                if let (Some(hp), Some(maxhp)) = (e.hp, e.maxhp) {
                    let maxx = window_size().unwrap().rows;
                    for x in 0..maxx {
                        queue!(
                            stdout,
                            MoveTo(x, 30),
                            SetForegroundColor(Color::White),
                            if ((hp as f32) / (maxhp as f32)) > ((x as f32) / (maxx as f32)) {
                                Print("=")
                            } else {
                                Print("-")
                            }
                        )
                        .unwrap();
                    }
                }
            }
        }

        for (id, message) in s.chat.iter().enumerate() {
            queue!(
                stdout,
                MoveTo(30, id as u16),
                SetForegroundColor(Color::Red),
                Print(&message.sender),
                Print(": "),
                SetForegroundColor(Color::White),
                Print(&message.message)
            )
            .unwrap();
        }

        if self.commanding {
            queue!(
                stdout,
                MoveTo(0, 0),
                SetForegroundColor(Color::White),
                Print(format!(":{}", self.current_command))
            )
            .unwrap();
        }

        stdout.flush().unwrap();
        stdout.execute(EndSynchronizedUpdate).unwrap();
    }
}

impl Drop for Drawer {
    fn drop(&mut self) {
        disable_raw_mode().unwrap();
        execute!(stdout(), Show).unwrap();
    }
}
