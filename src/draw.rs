use std::io::{Write, stdout};

use crossterm::{
    ExecutableCommand, QueueableCommand,
    cursor::{Hide, MoveTo, Show},
    event::{Event, KeyCode, KeyEvent, KeyModifiers, poll, read},
    execute, queue,
    style::{Color, Print, SetForegroundColor},
    terminal::{
        self, BeginSynchronizedUpdate, EndSynchronizedUpdate, disable_raw_mode, enable_raw_mode,
        window_size,
    },
};

use crate::state::State;

enum InputMode {
    Normal,
    Command,
    Inventory,
}

pub struct Drawer {
    mode: InputMode,
    current_command: String,
    inventory_selected_index: usize,
}

#[derive(PartialEq)]
pub enum InputEvent {
    Quit,
    Move((i16, i16)),
    Attack(i32),
    Travel(i32),
    Pickup(i32),
    Drop(i32),
    Say(String),
}

impl Drawer {
    // Get the appropriate wall character based on adjacent walls
    fn get_wall_char(&self, s: &State, entity: &crate::state::WorldEntity) -> &'static str {
        // Check for walls in all 8 directions (N, NE, E, SE, S, SW, W, NW)
        let directions = [
            (0, -1),  // North
            (1, -1),  // Northeast
            (1, 0),   // East
            (1, 1),   // Southeast
            (0, 1),   // South
            (-1, 1),  // Southwest
            (-1, 0),  // West
            (-1, -1), // Northwest
        ];
        
        // We mostly care about cardinal directions for box drawing
        let mut north = false;
        let mut east = false;
        let mut south = false;
        let mut west = false;
        
        for (idx, (dx, dy)) in directions.iter().enumerate() {
            let adjacent_wall = s.entities.iter().any(|e| 
                e.x == entity.x + dx && 
                e.y == entity.y + dy && 
                e.species.as_deref() == Some("wall") &&
                e.room_id == entity.room_id
            );
            
            // Set cardinal direction flags
            match idx {
                0 => north = adjacent_wall, // North
                2 => east = adjacent_wall,  // East
                4 => south = adjacent_wall, // South
                6 => west = adjacent_wall,  // West
                _ => {}  // We ignore diagonals for basic box drawing
            }
        }
        
        // Return the appropriate double-line box drawing character based on adjacent walls
        match (north, east, south, west) {
            (true, true, true, true) => "╬", // All four directions
            (true, true, true, false) => "╠", // North, East, South
            (true, true, false, true) => "╩", // North, East, West
            (true, false, true, true) => "╣", // North, South, West
            (false, true, true, true) => "╦", // East, South, West
            (true, true, false, false) => "╚", // North, East
            (true, false, true, false) => "║", // North, South
            (true, false, false, true) => "╝", // North, West
            (false, true, true, false) => "╔", // East, South
            (false, true, false, true) => "═", // East, West
            (false, false, true, true) => "╗", // South, West
            (true, false, false, false) => "║", // North only
            (false, true, false, false) => "═", // East only
            (false, false, true, false) => "║", // South only
            (false, false, false, true) => "═", // West only
            (false, false, false, false) => "■", // No connections (isolated wall)
        }
    }

    pub fn new() -> Self {
        let mut stdout = stdout();
        enable_raw_mode().unwrap();
        execute!(stdout, SetForegroundColor(Color::White), Hide,).unwrap();
        Self {
            mode: InputMode::Normal,
            current_command: String::new(),
            inventory_selected_index: 0,
        }
    }

    pub fn fetch_events(&mut self, s: &State) -> Vec<InputEvent> {
        let mut events = vec![];
        let self_entity = s
            .entities
            .iter()
            .find(|e| Some(e.entity_id) == s.self_entity_id);
        if poll(std::time::Duration::from_secs(0)).unwrap() {
            let event = read().unwrap();
            match event {
                Event::Key(KeyEvent {
                    code: KeyCode::Char('c'),
                    modifiers,
                    ..
                }) if modifiers & KeyModifiers::CONTROL == KeyModifiers::CONTROL => {
                    events.push(InputEvent::Quit);
                }
                _ => {}
            }
            if let Some(self_entity) = self_entity {
                let mut loc = None;
                let mut travel = false;
                let mut pickup = false;
                match self.mode {
                    InputMode::Command => match event {
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
                            self.mode = InputMode::Normal;
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
                    },
                    InputMode::Inventory => match event {
                        Event::Key(KeyEvent {
                            code: KeyCode::Esc, ..
                        }) => {
                            self.mode = InputMode::Normal;
                            self.inventory_selected_index = 0;
                        }
                        Event::Key(KeyEvent {
                            code: KeyCode::Char('j'), ..
                        }) => {
                            let inventory_count = s.entities
                                .iter()
                                .filter(|e| Some(e.room_id) == s.self_entity_id)
                                .count();
                            if inventory_count > 0 {
                                self.inventory_selected_index = (self.inventory_selected_index + 1) % inventory_count;
                            }
                        }
                        Event::Key(KeyEvent {
                            code: KeyCode::Char('k'), ..
                        }) => {
                            let inventory_count = s.entities
                                .iter()
                                .filter(|e| Some(e.room_id) == s.self_entity_id)
                                .count();
                            if inventory_count > 0 {
                                self.inventory_selected_index = if self.inventory_selected_index == 0 {
                                    if inventory_count > 0 { inventory_count - 1 } else { 0 }
                                } else {
                                    self.inventory_selected_index - 1
                                };
                            }
                        }
                        Event::Key(KeyEvent {
                            code: KeyCode::Char('d'), ..
                        }) => {
                            let inventory = s.entities
                                .iter()
                                .filter(|e| Some(e.room_id) == s.self_entity_id)
                                .collect::<Vec<_>>();
                            
                            if !inventory.is_empty() && self.inventory_selected_index < inventory.len() {
                                let item = inventory[self.inventory_selected_index];
                                events.push(InputEvent::Drop(item.entity_id));
                                // Exit inventory mode after dropping
                                self.mode = InputMode::Normal;
                                self.inventory_selected_index = 0;
                            }
                        }
                        _ => {}
                    },
                    InputMode::Normal => {
                        match event {
                            Event::Key(KeyEvent {
                                code: KeyCode::Char('i'),
                                ..
                            }) => {
                                self.mode = InputMode::Inventory;
                            }
                            Event::Key(KeyEvent {
                                code: KeyCode::Char(':'),
                                ..
                            }) => {
                                self.current_command = String::new();
                                self.mode = InputMode::Command;
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
                            if let Some(target) = s.entities.iter().find(|e| {
                                e.x == self_entity.x && e.y == self_entity.y && e.ends.is_some()
                            }) {
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
        let mut sorted_entities: Vec<&_> = s
            .entities
            .iter()
            .map(|e| e)
            .filter(|e| Some(e.room_id) != s.self_entity_id)
            .collect();
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
                            (_, Some("gold"), _) => Color::Yellow,
                            (_, _, _) => Color::White,
                        }),
                        Print(match (species.as_str(), e.hp) {
                            (_, Some(hp)) if hp <= 0 => "%",
                            ("human", _) => "@",
                            ("door", _) => "║",
                            ("snake", _) => "s",
                            ("floor", _) => "+",
                            ("wall", _) => self.get_wall_char(s, e),
                            ("upstair", _) => "<",
                            ("gold", _) => "$",
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

        match self.mode {
            InputMode::Normal => {
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
            }

            InputMode::Inventory => {
                queue!(
                    stdout,
                    MoveTo(30, 0),
                    SetForegroundColor(Color::White),
                    Print("Inventory")
                )
                .unwrap();
                let inventory = s
                    .entities
                    .iter()
                    .filter(|e| Some(e.room_id) == s.self_entity_id)
                    .collect::<Vec<_>>();
                
                for (i, e) in inventory.iter().enumerate() {
                    let item_color = match e.species.as_deref() {
                        Some("gold") => Color::Yellow,
                        _ => Color::White
                    };
                    
                    queue!(
                        stdout,
                        MoveTo(32, (i + 1) as u16),
                        SetForegroundColor(if i == self.inventory_selected_index { Color::Yellow } else { item_color }),
                        Print(format!("{}{}", 
                            if i == self.inventory_selected_index { "> " } else { "  " },
                            e.species.as_deref().unwrap_or("")
                        ))
                    )
                    .unwrap();
                }
            }
            InputMode::Command => {
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
                queue!(
                    stdout,
                    MoveTo(0, 0),
                    SetForegroundColor(Color::White),
                    Print(format!(":{}", self.current_command))
                )
                .unwrap();
            }
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
