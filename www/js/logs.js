$(document).ready(function(){
	$('#log-contents,.hour-contents').addClass('no-ll0')
	console.log('script file loaded', $('#logDate').text())
	$('.filter').change(function(){
		var fn=$(this).attr('name'), ic=$(this).is(':checked')
		$('#log-contents')[ic?'removeClass':'addClass'](fn)
		$('.hour-contents')[ic?'removeClass':'addClass'](fn)
		console.log(fn)
	})
	$('#logDate').parent('h1').append('<button id="a1d" title="go ahead one day">></button>')
	$('#logDate').parent('h1').prepend('<button id="b1d" title="go back one day"><</button>')
	$('#logDate').parent('h1').append('<button id="c1d" title="go to current hour log">Hour</button>')
	$('#logDate').parent('h1').append('<button id="d1d" title="go to current day log">Today</button>')
	$( "input[name*='no-errors']" ).parents('label').append(' ('+$('.err').length+')')
	$( "input[name*='no-ll0']" ).attr('checked', false)
	$( "input[name*='no-ll0']" ).parents('label').append(' ('+$('.ll0').length+')')
	$( "input[name*='no-ll1']" ).parents('label').append(' ('+$('.ll1').length+')')
	$( "input[name*='no-ll2']" ).parents('label').append(' ('+$('.ll2').length+')')
	$('#b1d, #a1d').click(function(){
		var newLog=NewDate($('#logDate').text(),$(this).attr('id')=='a1d'?1:-1)
		window.location=FormattedDate(newLog)+'.html'
	})
	$('#c1d').click(function(){
		window.location='latest-log.html'
	})
	$('#d1d').click(function(){
		window.location='day-log.html'
	})
	$('.hour-contents p').click(function(){
		$(this).parents('.hour-contents').toggleClass('showing')
	})
})
function NewDate(dt,o){
	var nd=dt.split('-')
	return new Date(nd[0],nd[1]*1-1,nd[2]*1+o)
}

function FormattedDate(d,v){
	var days=['Sun ','Mon ','Tue ','Wed ','Thu ','Fri ','Sat ']
	var months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
	var sep=$('#dateSep').val()||'-'
	var da=days[d.getDay()],dn=TwoD(d.getDate()),m=TwoD(d.getMonth()+1),mn=months[d.getMonth()],y=d.getFullYear(),arr=[]

	switch (v) {
		case 0:
			arr=[mn,dn,y]
			break
		case 0:
			arr=[mn,dn,y]
			break
		case 1:
			arr=[dn,mn,y]
			break
		case 2:
			arr=[dn,m,y]
			break
		case 3:
			sep=' '
			arr=[mn,dn]
			break
		default:
			arr=[y,m,dn]
			break
	}
	return arr.join(sep)
}

function TwoD(v){
	return ('0'+Number(v)).slice(-2)
}
