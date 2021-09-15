'use strict';
'require view';
'require poll';
'require ui';
'require uci';
'require rpc';
'require form';

var callInitList, callInitAction, callTimezone, setHostname,
    callGetLocaltime, callSetLocaltime, CBILocalTime;

callInitList = rpc.declare({
	object: 'luci',
	method: 'getInitList',
	params: [ 'name' ],
	expect: { '': {} },
	filter: function(res) {
		for (var k in res)
			return +res[k].enabled;
		return null;
	}
});

callInitAction = rpc.declare({
	object: 'luci',
	method: 'setInitAction',
	params: [ 'name', 'action' ],
	expect: { result: false }
});

callGetLocaltime = rpc.declare({
	object: 'luci',
	method: 'getLocaltime',
	expect: { result: 0 }
});

callSetLocaltime = rpc.declare({
	object: 'luci',
	method: 'setLocaltime',
	params: [ 'localtime' ],
	expect: { result: 0 }
});

callTimezone = rpc.declare({
	object: 'luci',
	method: 'getTimezones',
	expect: { '': {} }
});

setHostname = rpc.declare({
	object: 'system',
	method: 'hostname',
	params: [ 'hostname' ]
});

CBILocalTime = form.DummyValue.extend({
	renderWidget: function(section_id, option_id, cfgvalue) {
		return E([], [
			E('input', {
				'id': 'localtime',
				'type': 'text',
				'readonly': true,
				'value': new Date(cfgvalue * 1000).toLocaleString()
			}),
			E('br'),
			E('span', { 'class': 'control-group' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() {
						return callSetLocaltime(Math.floor(Date.now() / 1000));
					}),
					'disabled': (this.readonly != null) ? this.readonly : this.map.readonly
				}, _('Sync with browser')),
				' ',
				this.ntpd_support ? E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() {
						return callInitAction('sysntpd', 'restart');
					}),
					'disabled': (this.readonly != null) ? this.readonly : this.map.readonly
				}, _('Sync with NTP-Server')) : ''
			])
		]);
	},
});

return view.extend({
	load: function() {
		return Promise.all([
			callInitList('sysntpd'),
			callTimezone(),
			callGetLocaltime(),
			uci.load('luci'),
			uci.load('system')
		]);
	},

	render: function(rpc_replies) {
		var ntpd_enabled = rpc_replies[0],
		    timezones = rpc_replies[1],
		    localtime = rpc_replies[2],
		    m, s, o;

		m = new form.Map('system',
			_('System'),
			_('Here you can configure the basic aspects of your device like its hostname or the timezone.'));

		m.chain('luci');

		s = m.section(form.TypedSection, 'system', _('System Properties'));
		s.anonymous = true;
		s.addremove = false;

		s.tab('general', _('General Settings'));
		// s.tab('logging', _('Logging'));
		// s.tab('timesync', _('Time Synchronization'));
		s.tab('language', _('Language and Style'));

		/*
		 * System Properties
		 */

		o = s.taboption('general', CBILocalTime, '_systime', _('Local Time'));
		o.cfgvalue = function() { return localtime };
		o.ntpd_support = ntpd_enabled;

		o = s.taboption('general', form.Value, 'hostname', _('Hostname'));
		o.datatype = 'hostname';
		o.write = function(section_id, formvalue){
			setHostname(formvalue)
			return this.map.data.set(
				this.uciconfig || this.section.uciconfig || this.map.config,
				this.ucisection || section_id,
				this.ucioption || this.option,
				formvalue);
		}

		/* could be used also as a default for LLDP, SNMP "system description" in the future */
		o = s.taboption('general', form.Value, 'description', _('Description'), _('An optional, short description for this device'));
		o.optional = true;

		o = s.taboption('general', form.TextValue, 'notes', _('Notes'), _('Optional, free-form notes about this device'));
		o.optional = true;

		o = s.taboption('general', form.ListValue, 'zonename', _('Timezone'));
		o.value('UTC');

		var zones = Object.keys(timezones || {}).sort();
		for (var i = 0; i < zones.length; i++)
			o.value(zones[i]);

		o.write = function(section_id, formvalue) {

			var tz = timezones[formvalue] ? timezones[formvalue].tzstring : null;
			uci.set('system', section_id, 'zonename', formvalue);
			uci.set('system', section_id, 'timezone', tz);
		};

		/*
		 * Language & Style
		 */

		o = s.taboption('language', form.ListValue, '_lang', _('Language'))
		o.uciconfig = 'luci';
		o.ucisection = 'main';
		o.ucioption = 'lang';
		o.value('auto');

		var k = Object.keys(uci.get('luci', 'languages') || {}).sort();
		for (var i = 0; i < k.length; i++)
			if (k[i].charAt(0) != '.')
				o.value(k[i], uci.get('luci', 'languages', k[i]));

		o = s.taboption('language', form.ListValue, '_mediaurlbase', _('Design'))
		o.uciconfig = 'luci';
		o.ucisection = 'main';
		o.ucioption = 'mediaurlbase';

		var k = Object.keys(uci.get('luci', 'themes') || {}).sort();
		for (var i = 0; i < k.length; i++)
			if (k[i].charAt(0) != '.')
				o.value(uci.get('luci', 'themes', k[i]), k[i]);

		return m.render().then(function(mapEl) {
			poll.add(function() {
				return callGetLocaltime().then(function(t) {
					mapEl.querySelector('#localtime').value = new Date(t * 1000).toLocaleString();
				});
			});

			return mapEl;
		});
	}
});
