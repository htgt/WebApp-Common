// Genoverse tracks which can be used in both LIMS2 and WGE

Genoverse.Track.Genes = Genoverse.Track.extend({
    info   : 'Ensembl API genes & transcripts, see <a href="http://rest.ensembl.org/" target="_blank">rest.ensembl.org</a> for more details',
    // Different settings for different zoom level
    2000000: { // This one applies when > 2M base-pairs per screen
      labels : false
    },
    100000: { // more than 100K but less then 2M
      labels : true,
      model  : Genoverse.Track.Model.Gene.Ensembl,
      view   : Genoverse.Track.View.Gene.Ensembl
    },
    1: { // > 1 base-pair, but less then 100K
      labels : true,
      model  : Genoverse.Track.Model.Transcript.Ensembl,
      view   : Genoverse.Track.View.Transcript.Ensembl
    },
    populateMenu : function (feature) {
      var atts = {
        ID     : feature.id,
        Name   : feature.external_name,
        Description : feature.description,
        Parent : feature.Parent,
        Start  : feature.start,
        End    : feature.end,
        Strand : feature.strand,
        Type   : feature.feature_type,
        Biotype: feature.biotype,
        Source : feature.source,
        Logic  : feature.logic_name
      };
      return atts;
    },
    drawFeature: function(transcript, featureContext, labelContext, scale) {
      this.base(transcript, featureContext, labelContext, scale);

      //get correct arrow character
      var s = transcript.strand == -1 ? String.fromCharCode(9668) : String.fromCharCode(9658);
      var textWidth = Math.ceil(featureContext.measureText(s).width) + 1;
      var havana = transcript.logic_name.indexOf('ensembl_havana') === 0;
      featureContext.fillStyle = havana ? '#666666' : '#CCCCCC';
      //loop through all coding regions
      if (transcript.cds && transcript.cds.length) {
        for (i = 0; i < transcript.cds.length; i++) {
          cds = transcript.cds[i];

          var cds_start = transcript.x + (cds.start - transcript.start) * scale;
          var cds_end   = cds_start + ( (cds.end - cds.start) * scale );
          var cds_width = Math.max(1, (cds.end - cds.start) * scale);

          //don't show arrows if the box is too small
          if ( cds_width < (textWidth+1)*3 )
            continue;

          featureContext.fillText(
            s,
            cds_start + 1,
            transcript.y - 2 //no idea why but -2 is what works
          );

          featureContext.fillText(
            s,
            (cds_end - textWidth) + 1,
            transcript.y - 2
          );
        }
      }
    }
});

Genoverse.Track.Crisprs = Genoverse.Track.extend({
    model     : Genoverse.Track.Model.Transcript.GFF3,
    view      : Genoverse.Track.View.Transcript.extend({
      color : '#FFFFFF'
    }),
    autoHeight : true,
    height    : 150,
    labels    : false,
    threshold : 3000,
    messages  : { threshold : 'Crisprs not displayed for regions larger than ' },

    populateMenu : function (f) {
      // get up to date feature object
      var feature = this.track.model.featuresById[f.id];

      var report_link = "<a href='" + this.track.crispr_report_uri + "/" + feature.name
                                + "' target='_blank'><font color='#00FFFF'>Crispr Report</font></a>";
      var atts = {
          Start  : feature.start,
          End    : feature.end,
          Strand : feature.strand,
          Name   : feature.name,
          URL : report_link
      };
      if (feature.ot_summary){
        atts['Off-Targets'] = feature.ot_summary;
      }
      else {
        atts['Off-Targets'] = 'not computed';
      }
      return atts;
    },

    reload : function (){
        reload_track(this);
    }
});

Genoverse.Track.CrisprPairs = Genoverse.Track.extend({
    model     : Genoverse.Track.Model.Transcript.GFF3,
    view      : Genoverse.Track.View.Transcript.extend({
      color : '#FFFFFF',
      drawIntron: function (intron, context) {
        // We have set default view color to white as we do not want lines
        // around each crispr but we need to set strokeStlye to black to
        // draw the line connecting the paired crisprs
        var orig_strokeStyle = context.strokeStyle;
        context.strokeStyle = '#000000';
        this.base.apply(this, arguments);
        context.strokeStyle = orig_strokeStyle;
      }
    }),
    autoHeight : true,
    height    : 150,
    labels    : false,
    threshold : 3000,
    messages  : { threshold : 'Crispr pairs not displayed for regions larger than ' },

    populateMenu : function (f) {
        // get up to date feature object
        var feature = this.track.model.featuresById[f.id];
        var report_link = "<a href='" + this.track.pair_report_uri + "/"
                                + feature.name
                                + "?spacer=" + feature.spacer
                                + "' target='_blank'><font color='#00FFFF'>Crispr Pair Report</font></a>";
        var atts = {
            Start  : feature.start,
            End    : feature.end,
            Strand : feature.strand,
            Spacer : feature.spacer,
            Name   : feature.name,
            URL    : report_link,
            'Off-Targets: Pairs' : feature.ot_summary || 'not computed',
            Left   : feature.left_ot_summary,
            Right  : feature.right_ot_summary
        };
        return atts;
    },

    reload : function (){
        reload_track(this);
    }
});

Genoverse.Track.Model.Protein = Genoverse.Track.Model.extend({
  threshold : 10000,
  messages  : { threshold : 'Protein not displayed for regions larger than 10000' },
  buffer    : 0,
  //url       : 'http://t87-dev.internal.sanger.ac.uk:3001/api/translation_for_region?species=human&chr_name=__CHR__&chr_start=__START__&chr_end=__END__',

  parseData: function (data, start, end) {
    var index = 1;
    for ( var i = 0; i < data.length; i++ ) {
      this.insertFeature( data[i] );
    }
  },

  receiveData: function (data, start, end) {
    if ( data.error ) {
      create_alert(data.error);
    }
    else {
      this.base(data, start, end);
    }
  }
});

Genoverse.Track.View.Protein = Genoverse.Track.View.Sequence.extend({
  colors: {
    'default': '#CCCCCC',
    A: '#77dd88', G: '#77dd88',
    C: '#99ee66',
    D: '#55bb33', E: '#55bb33', N: '#55bb33', Q: '#55bb33',
    I: '#66bbff', L: '#66bbff', M: '#66bbff', V: '#66bbff',
    F: '#9999ff', W: '#9999ff', Y: '#9999ff',
    H: '#5555ff',
    K: '#ffcc77', R: '#ffcc77',
    P: '#eeaaaa',
    S: '#ff4455', T: '#ff4455',
    "*": '#ff0000'
  },
  labelColors: { 'default': '#000000'},

  init: function () {
    this.base();

    //add some classes to allow colouring of protein text
    var style = ".mutation { margin-right: 8px; }\n\
                 .mutation-highlighted { background-color: #ff0000 }\n";
    for ( var c in this.colors ) {
      color = this.colors[c];
      //create css classes like .protein_A { color:#77dd88 };
      style += '.protein_' + c + ' { color:'+ color +'; }\n';
    }

    $("<style type='text/css'>" + style + "</style>").appendTo("head");

  },

  //$("<style type='text/css'> .redbold{ color:#f00; font-weight:bold;} </style>").appendTo("head");

  draw: function (features, featureContext, labelContext, scale) {
    this.base(features, featureContext, labelContext, scale);

    //draw arrows
    //String.fromCharCode(9658); >
    //String.fromCharCode(9668); <
  },

  _drawBase: function(data) {
    data.context.fillStyle = data.boxColour;
    data.context.fillRect(data.x, data.y, data.width, data.height);

    if ( ! data.drawLabels ) return;

    data.context.fillStyle = data.textColour;
    var x = data.x + (data.width - this.labelWidth[data.base]) / 2;
    data.context.fillText(data.base, this.getTextCenter(data, data.base), data.y+this.labelYOffset );

    //need to compute width of label

    //don't draw numbers if the box is too small to hold 3 numbers
    if ( this.measureText(data.context, 999) > data.width ) return;

    //if its white change the colour because it won't show up
    if ( data.textColour == '#FFFFFF' )
      data.context.fillStyle = '#55bb33';

    data.context.fillText( data.idx, this.getTextCenter(data, data.idx), data.y+data.height+this.labelYOffset );
  },

  measureText: function (context, text) {
    //if its a number we dont want to cache all numbers, so just cache the number of
    //digits, which is stored in id
    var id = text;
    if ( text % 1 === 0 ) {
      var id = text.toString().length; //number of digits in the string
    }

    //for a number we want to measure the original text not thenumber of digits
    var size = this.labelWidth[id] || Math.ceil(context.measureText(text).width) + 1;

    return size;
  },

  getTextCenter: function (data, text) {
    var labelWidth = this.measureText(data.context, text);

    return data.x + (data.width - labelWidth) / 2;
  },

  drawSequence: function (feature, context, scale, width) {
    var drawLabels = this.labelWidth[this.widestLabel] < width*3 - 1;
    var start, bp;

    //draw the first base if one is set
    if ( feature.start_base ) {
      //swap start/end if its -ve stranded
      var idx = feature.strand == -1
              ? feature.start_index + feature.num_amino_acids
              : feature.start_index - 1;

      this._drawBase({
        context: context,
        boxColour: '#666666',
        x: feature.position[scale].X - (feature.start_base.len * scale),
        y: feature.position[scale].Y,
        width: scale*feature.start_base.len,
        height: this.featureHeight,
        drawLabels: drawLabels,
        textColour: '#FFFFFF',
        base: feature.start_base.aa,
        idx: idx
      });
    }

    if ( feature.end_base ) {
      var idx = feature.strand == -1
              ? feature.start_index-1
              : feature.start_index + feature.num_amino_acids;

      this._drawBase({
        context: context,
        boxColour: '#666666',
        x: feature.position[scale].X + (feature.sequence.length*3 * scale),
        y: feature.position[scale].Y,
        width: scale*feature.end_base.len,
        height: this.featureHeight,
        drawLabels: drawLabels,
        textColour: '#FFFFFF',
        base: feature.end_base.aa,
        idx: idx
      });
    }

    width *= 3;

    for (var i = 0; i < feature.sequence.length; i++) {
      start = feature.position[scale].X + (i*3) * scale;

      if (start < -scale || start > context.canvas.width) {
        continue;
      }


      var pos = i;
      var idx = feature.start_index + i;
      //display backwards if -ve gene
      if ( feature.strand == -1 ) {
        pos = ( feature.sequence.length - 1 ) - i;
        idx = ( feature.start_index + (feature.num_amino_acids-1) ) - i;
      }

      bp = feature.sequence.charAt(pos);

      this._drawBase({
        context: context,
        boxColour: (this.colors[bp] || this.colors['default']),
        x: start,
        y: feature.position[scale].Y,
        width: width,
        height: this.featureHeight,
        drawLabels: drawLabels,
        textColour: (this.labelColors[bp] || this.labelColors['default']),
        base: bp,
        idx: idx
      });
    }
  }

});

function reload_track(track){

    // update URL with latest params
    track.model.setURL(track.urlParams, true);

    var genoverse = track.browser;
    track.controller.resetImages();

    // clear out all existing data and features so they are regenerated
    track.model.dataRanges = new track.model.dataRanges.constructor;
    track.model.features = new track.model.features.constructor;
    track.model.featuresById = {};

    // clear out the image_container divs
    track.controller.imgContainers.empty();

    // redraw the track
    track.controller.makeFirstImage();
}