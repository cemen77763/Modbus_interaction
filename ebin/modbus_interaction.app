{application, modbus_interaction,
 [
    {description, "Application to interact with modbus TCP devices"},
    {vsn, "1.2.1"},
    {modules, []},
    {registered, [modbus]},
    {mod, {modbus_interaction, []}},
    {applications,
      [kernel,
       stdlib
      ]},
    {env,[]},
    {modules, []},

    {licenses, ["Apache 2.0"]},
    {links, []}
 ]}.
